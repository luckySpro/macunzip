# MacUnZip for Windows

Rust + Tauri 2。`core/` 是不依赖界面的压缩 / 解压核心，`app/` 是 Tauri 外壳，`ui/` 是静态前端（无需 npm 构建）。

```sh
cargo test -p muz-core                            # 核心测试，任何平台都能跑
cd app && npx @tauri-apps/cli@2 build --bundles nsis   # 在 Windows 上打包安装程序
```

- 右键菜单与文件关联由 NSIS 安装程序写入当前用户注册表（`app/installer-hooks.nsh`），卸载时清除。
- 资源管理器多选时每个文件会启动一个进程，程序用单实例插件合并 400 ms 内收到的文件。
- 设置保存在 `%APPDATA%\com.luckyspro.macunzip\settings.json`。
- 升级检查读取仓库默认分支 `update.json` 的 `windows` 段，规则与 Mac 版相同。

发布：在 GitHub Actions 中手动运行 Windows 工作流并填写 `win-vX.Y.Z`，版本号须与 `Cargo.toml` 一致。
