import SwiftUI
import UniformTypeIdentifiers

/// 压缩包内容预览：勾选要解压的文件，选目标位置后解压。
@MainActor
final class PreviewModel: ObservableObject {
    enum LoadState { case loading, loaded, needsPassword, failed(String) }

    let archive: URL
    @Published var state: LoadState = .loading
    @Published var entries: [ArchiveEngine.Entry] = []
    /// 勾选的路径；勾选目录等于勾选其下全部内容。
    @Published var checked: Set<String> = []
    @Published var collapsed: Set<String> = []
    @Published var password = ""
    @Published var folderID: UUID? = SharedSettings.shared.defaultExtractFolderID

    init(archive: URL) {
        self.archive = archive
        load()
    }

    func load() {
        state = .loading
        let archive = archive
        let password = password.isEmpty ? nil : password
        Task.detached {
            do {
                let entries = try ArchiveEngine.list(archive, password: password)
                await MainActor.run {
                    self.entries = entries
                    self.checked = Set(entries.filter { $0.depth == 0 }.map(\.path))
                    self.state = .loaded
                }
            } catch ArchiveError.passwordRequired, ArchiveError.wrongPassword {
                await MainActor.run { self.state = .needsPassword }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    /// 折叠目录后可见的条目。
    var visibleEntries: [ArchiveEngine.Entry] {
        entries.filter { entry in
            !collapsed.contains { entry.path.hasPrefix($0 + "/") }
        }
    }

    func isChecked(_ entry: ArchiveEngine.Entry) -> Bool {
        ArchiveEngine.isSelected(entry.path, in: checked)
    }

    func toggle(_ entry: ArchiveEngine.Entry) {
        if isChecked(entry) {
            // 取消勾选：去掉自己和子项；若是被父目录带上的，把父目录拆成其余兄弟项
            checked = checked.filter { $0 != entry.path && !$0.hasPrefix(entry.path + "/") }
            var path = entry.path
            while let parent = parentPath(of: path) {
                if checked.remove(parent) != nil {
                    for sibling in entries where parentPath(of: sibling.path) == parent && sibling.path != path {
                        checked.insert(sibling.path)
                    }
                }
                path = parent
            }
        } else {
            checked = checked.filter { !$0.hasPrefix(entry.path + "/") }
            checked.insert(entry.path)
        }
    }

    func toggleCollapse(_ entry: ArchiveEngine.Entry) {
        if collapsed.remove(entry.path) == nil { collapsed.insert(entry.path) }
    }

    var allChecked: Bool { entries.allSatisfy(isChecked) }

    func checkAll(_ on: Bool) {
        checked = on ? Set(entries.filter { $0.depth == 0 }.map(\.path)) : []
    }

    var selectionSummary: String {
        let files = entries.filter { !$0.isDirectory && isChecked($0) }
        let bytes = files.reduce(Int64(0)) { $0 + $1.size }
        return "已选 \(files.count) 个文件，\(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    func extract() {
        let destination = MainModel.shared.destinationURL(for: folderID)
        JobQueue.shared.extract([archive], to: destination,
                                only: allChecked ? nil : checked,
                                knownPassword: password.isEmpty ? nil : password)
    }

    private func parentPath(of path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }
}

struct PreviewView: View {
    @ObservedObject var model: PreviewModel
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .frame(minWidth: 460, minHeight: 360)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .loading:
            ProgressView("正在读取内容…").frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsPassword:
            VStack(spacing: 10) {
                Image(systemName: "lock").font(.system(size: 28)).foregroundStyle(.secondary)
                Text("这个压缩包的文件列表也加了密，请输入密码").font(.callout)
                SecureField("密码", text: $model.password).frame(width: 220).onSubmit { model.load() }
                Button("查看内容") { model.load() }.keyboardShortcut(.defaultAction)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            Text(message).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            List(model.visibleEntries) { entry in
                EntryRow(entry: entry, model: model)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Toggle("全选", isOn: Binding(get: { model.allChecked }, set: { model.checkAll($0) }))
                .toggleStyle(.checkbox)
            Text(model.selectionSummary).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Picker("解压到", selection: $model.folderID) {
                Text("原位置").tag(UUID?.none)
                ForEach(MainModel.shared.favorites) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .frame(width: 160)
            Button("解压") {
                model.extract()
                onClose()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.checked.isEmpty)
        }
        .padding(12)
    }
}

private struct EntryRow: View {
    let entry: ArchiveEngine.Entry
    @ObservedObject var model: PreviewModel

    var body: some View {
        HStack(spacing: 6) {
            Toggle("", isOn: Binding(get: { model.isChecked(entry) }, set: { _ in model.toggle(entry) }))
                .toggleStyle(.checkbox).labelsHidden()
            Color.clear.frame(width: CGFloat(entry.depth) * 16, height: 1)
            if entry.isDirectory {
                Button { model.toggleCollapse(entry) } label: {
                    Image(systemName: model.collapsed.contains(entry.path) ? "chevron.right" : "chevron.down")
                        .font(.caption2).frame(width: 10)
                }
                .buttonStyle(.plain)
                Image(systemName: "folder.fill").foregroundStyle(Theme.accent)
            } else {
                Color.clear.frame(width: 10, height: 1)
                Image(nsImage: NSWorkspace.shared.icon(for: .init(filenameExtension: (entry.name as NSString).pathExtension) ?? .data))
                    .resizable().frame(width: 16, height: 16)
            }
            Text(entry.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            if !entry.isDirectory {
                Text(ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .font(.callout)
    }
}
