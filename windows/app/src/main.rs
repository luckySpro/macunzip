// 发布版不弹出控制台窗口
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod settings;
mod update;

use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use muz_core::{CompressOptions, Error as CoreError};
use serde::Serialize;
use settings::Settings;
use tauri::{AppHandle, Emitter, Manager, State};
use tauri_plugin_dialog::DialogExt;

/// 资源管理器右键菜单 / 双击传进来的动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "kebab-case")]
enum Action {
    /// 双击压缩包：按设置直接解压或打开窗口
    DoubleClick,
    Open,
    ExtractHere,
    ExtractTo,
    QuickCompress,
    Compress,
}

#[derive(Clone, Serialize)]
struct Job {
    id: u64,
    title: String,
    state: &'static str, // running / done / failed
    result: Option<String>,
    message: Option<String>,
}

struct AppState {
    settings: Mutex<Settings>,
    jobs: Mutex<Vec<Job>>,
    next_id: AtomicUsize,
    active: AtomicUsize,
    /// 本次启动只是为了处理右键 / 双击，完成后自动退出
    background: AtomicBool,
    /// 收集同一次多选产生的多个进程传来的文件，合并成一批
    batch: Mutex<BTreeMap<Action, Vec<PathBuf>>>,
    batch_scheduled: AtomicBool,
    /// 等界面处理的请求；界面启动晚于请求时也不会丢
    requests: Mutex<Vec<UiRequest>>,
}

/// 交给界面处理：先存起来，再通知界面来取。
fn request(app: &AppHandle, req: UiRequest) {
    show_window(app);
    app.state::<AppState>().requests.lock().unwrap().push(req);
    let _ = app.emit("request", ());
}

/// 发给界面的事件：需要用户参与的请求。
#[derive(Clone, Serialize)]
#[serde(tag = "kind", rename_all = "kebab-case")]
enum UiRequest {
    Pending { files: Vec<String> },
    Compress { files: Vec<String> },
    Password { files: Vec<String>, dest: Option<String>, wrong: bool },
    Error { title: String, message: String },
}

fn parse_args(args: &[String]) -> Vec<(Action, PathBuf)> {
    let mut action = Action::DoubleClick;
    let mut out = Vec::new();
    for arg in args.iter().skip(1) {
        match arg.as_str() {
            "--open" => action = Action::Open,
            "--extract-here" => action = Action::ExtractHere,
            "--extract-to" => action = Action::ExtractTo,
            "--quick-compress" => action = Action::QuickCompress,
            "--compress" => action = Action::Compress,
            a if a.starts_with("--") => {}
            path => out.push((action, PathBuf::from(path))),
        }
    }
    out
}

fn queue(app: &AppHandle, items: Vec<(Action, PathBuf)>) {
    let state = app.state::<AppState>();
    {
        let mut batch = state.batch.lock().unwrap();
        for (action, path) in items {
            batch.entry(action).or_default().push(path);
        }
    }
    if !state.batch_scheduled.swap(true, Ordering::SeqCst) {
        let app = app.clone();
        std::thread::spawn(move || {
            std::thread::sleep(Duration::from_millis(400));
            let state = app.state::<AppState>();
            state.batch_scheduled.store(false, Ordering::SeqCst);
            let batch = std::mem::take(&mut *state.batch.lock().unwrap());
            for (action, files) in batch {
                run_action(&app, action, files);
            }
        });
    }
}

fn run_action(app: &AppHandle, action: Action, files: Vec<PathBuf>) {
    if update::is_required(app) {
        show_window(app);
        return;
    }
    let settings = app.state::<AppState>().settings.lock().unwrap().clone();
    let strings = |files: &[PathBuf]| files.iter().map(|p| p.display().to_string()).collect::<Vec<_>>();
    match action {
        Action::DoubleClick if settings.double_click_extract && settings.onboarded => {
            let dest = settings.destination(settings.default_folder);
            extract_all(app, files, dest, None);
        }
        Action::DoubleClick | Action::Open => {
            show_window(app);
            request(app, UiRequest::Pending { files: strings(&files) });
        }
        Action::ExtractHere => extract_all(app, files, None, None),
        Action::ExtractTo => {
            let start = files.first().and_then(|f| f.parent()).map(Path::to_path_buf);
            let mut dialog = app.dialog().file().set_title("选择解压位置");
            if let Some(dir) = start {
                dialog = dialog.set_directory(dir);
            }
            match dialog.blocking_pick_folder().and_then(|f| f.into_path().ok()) {
                Some(dir) => extract_all(app, files, Some(dir), None),
                None => quit_if_idle(app),
            }
        }
        Action::QuickCompress => compress_all(app, files, settings.compress.clone(), None, None),
        Action::Compress => {
            show_window(app);
            request(app, UiRequest::Compress { files: strings(&files) });
        }
    }
}

fn show_window(app: &AppHandle) {
    app.state::<AppState>().background.store(false, Ordering::SeqCst);
    if let Some(w) = app.get_webview_window("main") {
        let _ = w.show();
        let _ = w.unminimize();
        let _ = w.set_focus();
    }
}

fn quit_if_idle(app: &AppHandle) {
    let state = app.state::<AppState>();
    if state.background.load(Ordering::SeqCst)
        && state.active.load(Ordering::SeqCst) == 0
        && !state.batch_scheduled.load(Ordering::SeqCst)
    {
        app.exit(0);
    }
}

fn start_job(app: &AppHandle, title: String) -> u64 {
    let state = app.state::<AppState>();
    let id = state.next_id.fetch_add(1, Ordering::SeqCst) as u64;
    state.active.fetch_add(1, Ordering::SeqCst);
    let mut jobs = state.jobs.lock().unwrap();
    jobs.insert(0, Job { id, title, state: "running", result: None, message: None });
    jobs.truncate(20);
    let _ = app.emit("jobs", jobs.clone());
    id
}

fn finish_job(app: &AppHandle, id: u64, result: Result<PathBuf, String>) {
    let state = app.state::<AppState>();
    {
        let mut jobs = state.jobs.lock().unwrap();
        if let Some(job) = jobs.iter_mut().find(|j| j.id == id) {
            match &result {
                Ok(path) => {
                    job.state = "done";
                    job.result = Some(path.display().to_string());
                }
                Err(message) => {
                    job.state = "failed";
                    job.message = Some(message.clone());
                }
            }
        }
        let _ = app.emit("jobs", jobs.clone());
    }
    state.active.fetch_sub(1, Ordering::SeqCst);
    let reveal = state.settings.lock().unwrap().reveal_after;
    match result {
        Ok(path) if reveal => reveal_in_explorer(&path),
        Err(message) => {
            show_window(app);
            request(app, UiRequest::Error { title: "处理失败".into(), message });
        }
        _ => {}
    }
    quit_if_idle(app);
}

/// 解压一批压缩包；需要密码时交给界面询问。
fn extract_all(app: &AppHandle, files: Vec<PathBuf>, dest: Option<PathBuf>, password: Option<String>) {
    let archives: Vec<_> = files.into_iter().filter(|f| muz_core::is_archive(f)).collect();
    if archives.is_empty() {
        show_window(app);
        request(app, UiRequest::Error { title: "无法解压".into(), message: "所选文件不是支持的压缩包。".into() });
        return;
    }
    for archive in archives {
        let app = app.clone();
        let dest = dest.clone();
        let password = password.clone();
        let title = archive.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
        let id = start_job(&app, title);
        std::thread::spawn(move || {
            let parent = dest.unwrap_or_else(|| archive.parent().map(Path::to_path_buf).unwrap_or_default());
            let result = muz_core::extract(&archive, &parent, password.as_deref());
            match result {
                Err(e @ (CoreError::PasswordRequired | CoreError::WrongPassword)) => {
                    // 不算失败：撤掉这条任务，请界面询问密码后重试
                    let state = app.state::<AppState>();
                    state.jobs.lock().unwrap().retain(|j| j.id != id);
                    let _ = app.emit("jobs", state.jobs.lock().unwrap().clone());
                    state.active.fetch_sub(1, Ordering::SeqCst);
                    request(&app, UiRequest::Password {
                        files: vec![archive.display().to_string()],
                        dest: Some(parent.display().to_string()),
                        wrong: matches!(e, CoreError::WrongPassword),
                    });
                }
                Ok(path) => {
                    if app.state::<AppState>().settings.lock().unwrap().delete_after_extract {
                        let _ = trash(&archive);
                    }
                    finish_job(&app, id, Ok(path));
                }
                Err(e) => finish_job(&app, id, Err(e.to_string())),
            }
        });
    }
}

fn compress_all(app: &AppHandle, files: Vec<PathBuf>, defaults: settings::CompressDefaults, password: Option<String>, name: Option<String>) {
    let Some(first) = files.first().cloned() else { return };
    let settings = app.state::<AppState>().settings.lock().unwrap().clone();
    let folder = settings.destination(defaults.destination).unwrap_or_else(|| first.parent().map(Path::to_path_buf).unwrap_or_default());
    let options = CompressOptions { format: defaults.format, level: defaults.level, exclude_system_files: defaults.exclude_system_files };
    let base = name.filter(|n| !n.trim().is_empty()).unwrap_or_else(|| {
        if files.len() == 1 { muz_core::base_name(&first) } else { "归档".into() }
    });
    let output = muz_core::unique_path(&folder.join(format!("{base}.{}", options.format.extension())));
    let title = output.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    let id = start_job(app, title);
    let app = app.clone();
    std::thread::spawn(move || {
        let result = muz_core::compress(&files, &output, &options, password.as_deref()).map(|_| output).map_err(|e| e.to_string());
        finish_job(&app, id, result);
    });
}

#[cfg(windows)]
fn reveal_in_explorer(path: &Path) {
    let _ = std::process::Command::new("explorer").arg(format!("/select,{}", path.display())).spawn();
}
#[cfg(not(windows))]
fn reveal_in_explorer(_: &Path) {}

/// 移到回收站：Windows 没有现成的标准库接口，这里交给 PowerShell 的 VisualBasic 方法。
#[cfg(windows)]
fn trash(path: &Path) -> std::io::Result<()> {
    use std::os::windows::process::CommandExt;
    let script = format!(
        "Add-Type -AssemblyName Microsoft.VisualBasic; [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile('{}','OnlyErrorDialogs','SendToRecycleBin')",
        path.display().to_string().replace('\'', "''")
    );
    std::process::Command::new("powershell").args(["-NoProfile", "-Command", &script]).creation_flags(0x0800_0000).status()?;
    Ok(())
}
#[cfg(not(windows))]
fn trash(_: &Path) -> std::io::Result<()> {
    Ok(())
}

// ---- 给界面调用的命令 ----

#[tauri::command]
fn get_settings(state: State<AppState>) -> Settings {
    state.settings.lock().unwrap().clone()
}

#[tauri::command]
fn save_settings(app: AppHandle, state: State<AppState>, settings: Settings) -> Result<(), String> {
    *state.settings.lock().unwrap() = settings.clone();
    settings.save(&app).map_err(|e| e.to_string())
}

#[tauri::command]
fn take_requests(state: State<AppState>) -> Vec<UiRequest> {
    std::mem::take(&mut *state.requests.lock().unwrap())
}

#[tauri::command]
fn get_jobs(state: State<AppState>) -> Vec<Job> {
    state.jobs.lock().unwrap().clone()
}

#[tauri::command]
fn extract(app: AppHandle, files: Vec<String>, dest: Option<String>, folder_id: Option<String>, password: Option<String>) -> Result<(), String> {
    if update::is_required(&app) {
        return Err("请先升级到最新版本".into());
    }
    let settings = app.state::<AppState>().settings.lock().unwrap().clone();
    let dest = dest.map(PathBuf::from).or_else(|| settings.destination(folder_id.and_then(|s| s.parse().ok())));
    extract_all(&app, files.into_iter().map(PathBuf::from).collect(), dest, password);
    Ok(())
}

#[tauri::command]
fn compress(app: AppHandle, files: Vec<String>, options: settings::CompressDefaults, password: Option<String>, name: Option<String>, save_default: bool) -> Result<(), String> {
    if update::is_required(&app) {
        return Err("请先升级到最新版本".into());
    }
    if save_default {
        let state = app.state::<AppState>();
        let mut s = state.settings.lock().unwrap();
        s.compress = options.clone();
        s.save(&app).map_err(|e| e.to_string())?;
    }
    compress_all(&app, files.into_iter().map(PathBuf::from).collect(), options, password.filter(|p| !p.is_empty()), name);
    Ok(())
}

#[tauri::command]
async fn pick_files(app: AppHandle, archives: bool) -> Vec<String> {
    let mut dialog = app.dialog().file().set_title(if archives { "选择压缩包" } else { "选择要压缩的文件" });
    if archives {
        dialog = dialog.add_filter("压缩包", &["zip", "rar", "7z", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz2", "zst", "tzst"]);
    }
    dialog
        .blocking_pick_files()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|f| f.into_path().ok())
        .map(|p| p.display().to_string())
        .collect()
}

#[tauri::command]
async fn pick_folder(app: AppHandle, title: String) -> Option<String> {
    app.dialog().file().set_title(title).blocking_pick_folder().and_then(|f| f.into_path().ok()).map(|p| p.display().to_string())
}

#[tauri::command]
fn reveal(path: String) {
    reveal_in_explorer(Path::new(&path));
}

#[tauri::command]
fn is_archive(path: String) -> bool {
    muz_core::is_archive(Path::new(&path))
}

#[tauri::command]
fn open_default_apps() {
    #[cfg(windows)]
    let _ = std::process::Command::new("explorer").arg("ms-settings:defaultapps").spawn();
}

#[tauri::command]
fn update_status(app: AppHandle) -> update::Status {
    update::status(&app)
}

#[tauri::command]
fn open_url(url: String) {
    if url.starts_with("https://") {
        #[cfg(windows)]
        let _ = std::process::Command::new("explorer").arg(url).spawn();
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_single_instance::init(|app, argv, _cwd| {
            let items = parse_args(&argv);
            if items.is_empty() {
                show_window(app);
            } else {
                queue(app, items);
            }
        }))
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            get_settings, save_settings, get_jobs, take_requests, extract, compress, pick_files, pick_folder,
            reveal, is_archive, open_default_apps, update_status, open_url
        ])
        .setup(|app| {
            let settings = Settings::load(app.handle());
            let args: Vec<String> = std::env::args().collect();
            let items = parse_args(&args);
            app.manage(AppState {
                settings: Mutex::new(settings),
                jobs: Mutex::new(Vec::new()),
                next_id: AtomicUsize::new(1),
                active: AtomicUsize::new(0),
                background: AtomicBool::new(!items.is_empty()),
                batch: Mutex::new(BTreeMap::new()),
                batch_scheduled: AtomicBool::new(false),
                requests: Mutex::new(Vec::new()),
            });
            update::start(app.handle().clone());
            if items.is_empty() {
                show_window(app.handle());
            } else {
                queue(app.handle(), items);
            }
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("MacUnZip 启动失败");
}
