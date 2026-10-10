# MacUnZip

一个原生、紧凑、“用完即走”的 macOS 解压缩工具。

- **双击即解压**：首次启动时选择双击压缩包的行为，可以直接解压到同一目录（不出现窗口），也可以打开主界面。
- **主窗口（方案 A）**：顶部切换解压和压缩，中间是拖放区，下方是可点击的常用目录。右键某个目录可以“设为默认位置”，也可以把文件直接拖到目录上。
- **访达右键菜单**：快速压缩（使用默认设置）、压缩…（可设格式、压缩率、密码，勾选“保存为默认设置”后下次免填）、解压到此处、解压到…。
- **内容预览**：查看压缩包里的文件，勾选需要的部分再解压。“打开主界面”模式下双击压缩包、或访达右键“预览内容…”都会打开它。
- **菜单栏入口（方案 C）**：在设置里开启后常驻菜单栏，常用目录做成磁贴，拖文件上去即执行。
- **格式**：解压支持 zip、7z、tar、gz、xz、bz2、zst、iso 等（libarchive），RAR / RAR5 含加密包使用官方 UnRAR 库。压缩支持 zip（可加 AES-256 密码）、7z、tar.gz、tar.zst。

## 构建

需要 Xcode 16 及以上，部署目标为 macOS 13。

```sh
brew install xcodegen libarchive   # libarchive 只用它的头文件，运行时链接系统自带的 /usr/lib/libarchive
./scripts/bootstrap.sh             # 下载并编译 UnRAR，生成 Xcode 工程
open MacUnZip.xcodeproj
```

在 `project.yml` 中填写 `DEVELOPMENT_TEAM`。App Group 使用 `<TeamID>.com.luckyspro.macunzip`，主程序和右键扩展共享设置都靠它。

运行后需要在“系统设置 › 通用 › 登录项与扩展 › 访达”中启用“MacUnZip 右键菜单”。

## 结构

| 目录 | 内容 |
| --- | --- |
| `App/` | 主程序：AppDelegate（处理双击、右键请求，任务完成后自动退出）、主窗口、首次启动、压缩面板、设置 |
| `App/Services/` | `JobQueue` 任务队列，`FolderAccess` 沙盒目录授权（安全作用域书签），`DefaultHandler` 设为默认打开方式 |
| `Shared/` | `ArchiveEngine` libarchive 封装，`SharedSettings` App Group 设置，`FinderRequest` 扩展与主程序之间的请求 |
| `FinderExtension/` | Finder Sync 扩展，只负责生成右键菜单并唤起主程序 |
| `CArchive/`、`CUnRAR/` | libarchive 与 UnRAR 的 Swift 模块映射 |
| `scripts/` | `bootstrap.sh` 准备依赖并生成工程，`fetch-unrar.sh` 下载编译 UnRAR |

每次推送都会在 GitHub Actions 的 macOS 环境里完整编译一次（`.github/workflows/build.yml`）。

## 沙盒说明

- 双击打开时，沙盒只授予压缩包本身的访问权限。为了能在原位置写入，首次启动会请用户授权个人文件夹并保存书签。个人文件夹以外的位置（如外接硬盘）在第一次用到时再单独请求授权。
- 右键扩展把请求写进 App Group 容器，再通过 `macunzip://request/<id>` 唤起主程序处理。

## 待办

- [ ] 7z 加密压缩：libarchive 不支持写入加密 7z，需要另接 7-Zip 引擎（LGPL，需评估上架方式）
- [ ] 上架前把 libarchive 改为静态链接自带版本，避免依赖系统版本的格式支持差异
- [ ] 应用图标与 App Store 截图
