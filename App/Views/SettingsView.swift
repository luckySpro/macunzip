import SwiftUI

/// 设置窗口：双击行为、默认位置（含自定义目录）、压缩默认值、配色。
struct SettingsView: View {
    @ObservedObject private var model = MainModel.shared
    @State private var behavior = SharedSettings.shared.doubleClickBehavior
    @State private var compress = SharedSettings.shared.compressDefaults
    @State private var isDefault = DefaultHandler.isDefaultForZip
    @State private var revealInFinder = SharedSettings.shared.revealInFinder
    @State private var trashAfterExtract = SharedSettings.shared.trashArchiveAfterExtract
    @AppStorage("showMenuBar", store: SharedSettings.shared.defaults) private var showMenuBar = false
    @AppStorage(Theme.storageKey, store: SharedSettings.shared.defaults) private var theme = Theme.system.rawValue

    var body: some View {
        Form {
            Section("通用") {
                Picker("双击压缩包时", selection: $behavior) {
                    Text("直接解压").tag(DoubleClickBehavior.extractInPlace)
                    Text("打开主界面").tag(DoubleClickBehavior.openWindow)
                }
                LabeledContent("默认打开方式") {
                    if isDefault {
                        Text("MacUnZip 已是默认").foregroundStyle(.secondary)
                    } else {
                        Button("设为默认") {
                            Task { _ = await DefaultHandler.makeDefault(); isDefault = DefaultHandler.isDefaultForZip }
                        }
                    }
                }
                Toggle("在菜单栏显示 MacUnZip", isOn: $showMenuBar)
                LabeledContent("个人文件夹权限") {
                    if FolderAccess.hasHomeAccess { Text("已授权").foregroundStyle(.secondary) }
                    else { Button("授权…") { FolderAccess.requestHomeAccess() } }
                }
            }

            Section("解压") {
                Picker("默认解压到", selection: $model.defaultFolderID) {
                    Text("原位置（压缩包所在目录）").tag(UUID?.none)
                    if !model.favorites.isEmpty { Divider() }
                    ForEach(model.favorites) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Toggle("完成后在访达中显示", isOn: $revealInFinder)
                Toggle("解压后把压缩包移到废纸篓", isOn: $trashAfterExtract)
            }

            Section("快速压缩的默认设置") {
                Picker("格式", selection: $compress.format) {
                    ForEach(ArchiveFormat.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("压缩率", selection: $compress.level) {
                    ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("存放到", selection: $compress.destination) {
                    Text("与原文件同目录").tag(CompressDestination.sameFolder)
                    if !model.favorites.isEmpty { Divider() }
                    ForEach(model.favorites) { Text($0.name).tag(CompressDestination.favorite($0.id)) }
                }
                Toggle("排除 .DS_Store 等系统文件", isOn: $compress.excludeMacMetadata)
            }

            Section {
                ForEach(model.favorites) { folder in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(folder.name)
                            Text(folder.path).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        if model.defaultFolderID == folder.id {
                            Text("默认").font(.caption).foregroundStyle(.secondary)
                        }
                        Button(role: .destructive) { model.remove(folder) } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        .help("从常用目录移除")
                    }
                }
                Button("添加目录…") { model.addFavorite() }
            } header: {
                Text("常用目录")
            } footer: {
                Text("这里的目录会出现在主窗口、菜单栏和压缩面板里，都可以设为默认位置。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("外观") {
                LabeledContent("配色") {
                    HStack(spacing: 10) {
                        ForEach(Theme.allCases) { item in
                            Swatch(theme: item, selected: theme == item.rawValue) { theme = item.rawValue }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
        .onChange(of: behavior) { SharedSettings.shared.doubleClickBehavior = $0 }
        .onChange(of: compress) { SharedSettings.shared.compressDefaults = $0 }
        .onChange(of: revealInFinder) { SharedSettings.shared.revealInFinder = $0 }
        .onChange(of: trashAfterExtract) { SharedSettings.shared.trashArchiveAfterExtract = $0 }
        .onChange(of: model.defaultFolderID) { model.selectedFolderID = $0 }
    }
}

/// 色卡里的一个颜色圆点。
private struct Swatch: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if theme == .system {
                    Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                                                  center: .center))
                } else {
                    Circle().fill(theme.color)
                }
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 20, height: 20)
            .overlay(Circle().strokeBorder(.primary.opacity(selected ? 0.5 : 0.1), lineWidth: selected ? 2 : 1).padding(-3))
        }
        .buttonStyle(.plain)
        .help(theme.name)
    }
}
