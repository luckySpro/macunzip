//! 版本检查与强制升级，规则与 Mac 版相同：
//! 读取仓库默认分支 update.json 里的 `windows` 段；当前版本低于 `minimum` 时界面锁定、拒绝新任务。
//! 最低版本记在设置里只升不降；断网沿用记录，从未取到清单则不拦截。

use std::sync::atomic::Ordering;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager};

use crate::AppState;

const MANIFEST_URL: &str = "https://raw.githubusercontent.com/luckySpro/macunzip/HEAD/update.json";

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Channel {
    pub latest: String,
    pub minimum: String,
    pub url: String,
    #[serde(default)]
    pub notes: String,
}

#[derive(Deserialize)]
struct Manifest {
    windows: Option<Channel>,
}

#[derive(Clone, Serialize)]
pub struct Status {
    pub current: String,
    pub latest: Option<String>,
    pub required: bool,
    pub url: Option<String>,
    pub notes: Option<String>,
}

static CHANNEL: std::sync::Mutex<Option<Channel>> = std::sync::Mutex::new(None);

pub fn current() -> &'static str {
    env!("CARGO_PKG_VERSION")
}

/// 逐段按数字比较，1.10.0 > 1.9.0。
pub fn older(a: &str, b: &str) -> bool {
    let parse = |s: &str| s.split('-').next().unwrap_or("").split('.').map(|p| p.parse::<u64>().unwrap_or(0)).collect::<Vec<_>>();
    let (x, y) = (parse(a), parse(b));
    for i in 0..x.len().max(y.len()) {
        let (l, r) = (x.get(i).copied().unwrap_or(0), y.get(i).copied().unwrap_or(0));
        if l != r {
            return l < r;
        }
    }
    false
}

pub fn is_required(app: &AppHandle) -> bool {
    let known = app.state::<AppState>().settings.lock().unwrap().known_minimum.clone();
    known.is_some_and(|m| older(current(), &m))
}

pub fn status(app: &AppHandle) -> Status {
    let channel = CHANNEL.lock().unwrap().clone();
    Status {
        current: current().into(),
        latest: channel.as_ref().map(|c| c.latest.clone()),
        required: is_required(app),
        url: channel.as_ref().map(|c| c.url.clone()),
        notes: channel.map(|c| c.notes),
    }
}

pub fn start(app: AppHandle) {
    std::thread::spawn(move || loop {
        refresh(&app);
        std::thread::sleep(Duration::from_secs(6 * 3600));
    });
}

fn refresh(app: &AppHandle) {
    let agent = ureq::AgentBuilder::new().timeout(Duration::from_secs(15)).build();
    let Ok(resp) = agent.get(MANIFEST_URL).set("User-Agent", &format!("MacUnZip/{}", current())).call() else { return };
    let Ok(manifest) = resp.into_json::<Manifest>() else { return };
    let Some(channel) = manifest.windows else { return };
    if !channel.url.starts_with("https://") {
        return;
    }
    let state = app.state::<AppState>();
    {
        let mut settings = state.settings.lock().unwrap();
        let raise = settings.known_minimum.as_deref().is_none_or(|known| older(known, &channel.minimum));
        if raise {
            settings.known_minimum = Some(channel.minimum.clone());
            let _ = settings.save(app);
        }
    }
    *CHANNEL.lock().unwrap() = Some(channel);
    if is_required(app) {
        state.background.store(false, Ordering::SeqCst);
        crate::show_window(app);
    }
    let _ = app.emit("update", status(app));
}

#[cfg(test)]
mod tests {
    #[test]
    fn compares_numerically() {
        assert!(super::older("0.9.0", "0.10.0"));
        assert!(!super::older("1.0", "1.0.0"));
        assert!(!super::older("1.2.0", "1.1.9"));
    }
}
