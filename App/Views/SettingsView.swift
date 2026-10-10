import SwiftUI

/// 设置窗口：双击行为、默认打开方式、压缩默认值。
struct SettingsView: View {
    @State private var behavior = SharedSettings.shared.doubleClickBehavior
    @State private var compress = SharedSettings.shared.compressDefaults
    @State private var isDefault = DefaultHandler.isDefaultForZip

    var body: some View {
        Form {
            Picker("双击压缩包时", selection: $behavior) {
                Text("直接解压到同一目录").tag(DoubleClickBehavior.extractInPlace)
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
            LabeledContent("个人文件夹权限") {
                if FolderAccess.hasHomeAccess { Text("已授权").foregroundStyle(.secondary) }
                else { Button("授权…") { FolderAccess.requestHomeAccess() } }
            }

            Section("快速压缩的默认设置") {
                Picker("格式", selection: $compress.format) {
                    ForEach(ArchiveFormat.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("压缩率", selection: $compress.level) {
                    ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("排除 .DS_Store 等系统文件", isOn: $compress.excludeMacMetadata)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onChange(of: behavior) { SharedSettings.shared.doubleClickBehavior = $0 }
        .onChange(of: compress) { SharedSettings.shared.compressDefaults = $0 }
    }
}
