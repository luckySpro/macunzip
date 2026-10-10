import SwiftUI

/// 访达右键“压缩…”弹出的小面板。勾选“保存为默认设置”后，
/// “快速压缩”和主窗口都会用这里的格式、压缩率和存放位置。
struct CompressPanel: View {
    let items: [URL]
    let onClose: () -> Void

    @State private var options = SharedSettings.shared.compressDefaults
    @State private var fileName: String
    @State private var password = ""
    @State private var saveAsDefault = false
    private let favorites = SharedSettings.shared.favorites

    init(items: [URL], onClose: @escaping () -> Void) {
        self.items = items
        self.onClose = onClose
        _fileName = State(initialValue: items.count == 1
                          ? items[0].deletingPathExtension().lastPathComponent : "归档")
    }

    var body: some View {
        VStack(spacing: 0) {
        Form {
            TextField("文件名", text: $fileName, prompt: Text("归档"))
                .overlay(alignment: .trailing) {
                    Text(".\(options.format.fileExtension)").foregroundStyle(.secondary).padding(.trailing, 6)
                }

            Picker("格式", selection: $options.format) {
                ForEach(ArchiveFormat.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            Picker("压缩率", selection: $options.level) {
                ForEach(CompressionLevel.allCases) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)

            SecureField("密码", text: $password, prompt: Text(options.format.supportsPassword ? "可不填" : "此格式不支持密码"))
                .disabled(!options.format.supportsPassword)

            Picker("存放到", selection: $options.destination) {
                Text("与原文件同目录").tag(CompressDestination.sameFolder)
                ForEach(favorites) { Text($0.name).tag(CompressDestination.favorite($0.id)) }
            }

            Toggle("排除 .DS_Store 等系统文件", isOn: $options.excludeMacMetadata)
        }
        .formStyle(.columns)
        .padding(.horizontal, 18)
        .padding(.top, 34)

        Divider().padding(.top, 12)

        HStack {
            Toggle("保存为默认设置", isOn: $saveAsDefault).toggleStyle(.checkbox)
            Spacer()
            Button("取消", action: onClose).keyboardShortcut(.cancelAction)
            Button("压缩", action: compress).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        }
        .frame(width: 380)
    }

    private func compress() {
        // 密码不存入默认设置
        if saveAsDefault { SharedSettings.shared.compressDefaults = options }
        let name = fileName.trimmingCharacters(in: .whitespaces)
        JobQueue.shared.compress(items, options: options, password: password.isEmpty ? nil : password,
                                 fileName: name.isEmpty ? nil : name)
        onClose()
    }
}
