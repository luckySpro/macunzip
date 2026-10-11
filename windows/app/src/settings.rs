//! 设置：存在 %APPDATA%\com.luckyspro.macunzip\settings.json。

use std::path::{Path, PathBuf};

use muz_core::{Format, Level};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Favorite {
    pub id: Uuid,
    pub name: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct CompressDefaults {
    pub format: Format,
    pub level: Level,
    /// None 表示与原文件同目录
    pub destination: Option<Uuid>,
    pub exclude_system_files: bool,
}

impl Default for CompressDefaults {
    fn default() -> Self {
        Self { format: Format::Zip, level: Level::Normal, destination: None, exclude_system_files: true }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    pub onboarded: bool,
    /// 双击压缩包时直接解压（否则打开窗口）
    pub double_click_extract: bool,
    pub favorites: Vec<Favorite>,
    /// 默认解压位置；None 表示原位置
    pub default_folder: Option<Uuid>,
    pub reveal_after: bool,
    pub delete_after_extract: bool,
    pub compress: CompressDefaults,
    pub theme: String,
    /// 已知的最低支持版本，只升不降
    pub known_minimum: Option<String>,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            onboarded: false,
            double_click_extract: true,
            favorites: suggested_favorites(),
            default_folder: None,
            reveal_after: true,
            delete_after_extract: false,
            compress: CompressDefaults::default(),
            theme: "system".into(),
            known_minimum: None,
        }
    }
}

fn suggested_favorites() -> Vec<Favorite> {
    let Some(home) = std::env::var_os("USERPROFILE").map(PathBuf::from) else { return Vec::new() };
    [("下载", "Downloads"), ("桌面", "Desktop"), ("文档", "Documents")]
        .iter()
        .map(|(_, dir)| home.join(dir))
        .zip(["下载", "桌面", "文档"])
        .filter(|(p, _)| p.is_dir())
        .map(|(p, name)| Favorite { id: Uuid::new_v4(), name: name.into(), path: p.display().to_string() })
        .collect()
}

fn file(app: &AppHandle) -> Option<PathBuf> {
    app.path().app_config_dir().ok().map(|d| d.join("settings.json"))
}

impl Settings {
    pub fn load(app: &AppHandle) -> Self {
        file(app)
            .and_then(|p| std::fs::read(p).ok())
            .and_then(|data| serde_json::from_slice(&data).ok())
            .unwrap_or_default()
    }

    pub fn save(&self, app: &AppHandle) -> std::io::Result<()> {
        let Some(path) = file(app) else { return Ok(()) };
        if let Some(dir) = path.parent() {
            std::fs::create_dir_all(dir)?;
        }
        // 先写临时文件再替换，避免写到一半损坏
        let tmp = path.with_extension("json.tmp");
        std::fs::write(&tmp, serde_json::to_vec_pretty(self).unwrap_or_default())?;
        std::fs::rename(tmp, path)
    }

    /// 常用目录 id 对应的路径；None 或目录已不存在时返回 None（即原位置）。
    pub fn destination(&self, id: Option<Uuid>) -> Option<PathBuf> {
        let id = id?;
        self.favorites.iter().find(|f| f.id == id).map(|f| PathBuf::from(&f.path)).filter(|p| Path::new(p).is_dir())
    }
}
