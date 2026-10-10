import AppKit

/// 一次解压或压缩任务，用于主窗口的“最近”列表。
struct Job: Identifiable {
    enum State: Equatable { case running, done(URL), failed(String) }
    let id = UUID()
    var title: String
    var progress: Double = 0
    var state: State = .running
}

/// 运行解压 / 压缩任务，处理权限、密码和完成后的收尾。
@MainActor
final class JobQueue: ObservableObject {
    static let shared = JobQueue()
    @Published private(set) var jobs: [Job] = []

    var isIdle: Bool { !jobs.contains { $0.state == .running } }
    /// 所有任务结束后调用；双击解压模式下用来退出应用。
    var onIdle: (() -> Void)?

    // MARK: 解压

    /// `destination` 为 nil 时解压到压缩包所在目录。
    /// `selection` 只解压其中的路径（来自内容预览）；`knownPassword` 为预览时已输入的密码。
    func extract(_ archives: [URL], to destination: URL? = nil,
                 only selection: Set<String>? = nil, knownPassword: String? = nil) {
        for archive in archives where ArchiveFormat.isArchive(archive) {
            let parent = destination ?? archive.deletingLastPathComponent()
            guard let endAccess = FolderAccess.beginAccess(toFolder: parent) else { continue }

            var password = knownPassword
            if password == nil, ArchiveEngine.needsPassword(archive) {
                guard let entered = PasswordPrompt.ask(for: archive) else { endAccess(); continue }
                password = entered
            }
            run(title: archive.lastPathComponent, cleanup: endAccess) { progress in
                let result = try ArchiveEngine.extract(archive, into: parent, password: password, only: selection, progress: progress)
                if selection == nil, SharedSettings.shared.trashArchiveAfterExtract {
                    try? FileManager.default.trashItem(at: archive, resultingItemURL: nil)
                }
                return result
            }
        }
        finishIfIdle()
    }

    // MARK: 压缩

    func compress(_ items: [URL], options: CompressDefaults, password: String?, fileName: String? = nil) {
        guard let first = items.first else { return }
        let folder: URL
        switch options.destination {
        case .sameFolder:
            folder = first.deletingLastPathComponent()
        case .favorite(let id):
            folder = SharedSettings.shared.favorites.first { $0.id == id }
                .flatMap { FolderAccess.resolve($0.bookmark) } ?? first.deletingLastPathComponent()
        }
        guard let endAccess = FolderAccess.beginAccess(toFolder: folder) else { return }

        let stem = fileName ?? (items.count == 1 ? first.deletingPathExtension().lastPathComponent : "归档")
        let output = ArchiveEngine.uniqueURL(folder.appendingPathComponent("\(stem).\(options.format.fileExtension)"))
        run(title: output.lastPathComponent, cleanup: endAccess) { progress in
            try ArchiveEngine.compress(items, to: output, format: options.format, level: options.level,
                                       password: options.format.supportsPassword ? password : nil,
                                       excludeMacMetadata: options.excludeMacMetadata, progress: progress)
            return output
        }
    }

    // MARK: 内部

    private func run(title: String, cleanup: @escaping () -> Void,
                     work: @escaping (@escaping ArchiveEngine.Progress) throws -> URL) {
        let job = Job(title: title)
        jobs.insert(job, at: 0)
        if jobs.count > 20 { jobs.removeLast() }

        Task.detached(priority: .userInitiated) {
            let report: ArchiveEngine.Progress = { value in
                Task { @MainActor in self.update(job.id) { $0.progress = value } }
            }
            let state: Job.State
            do { state = .done(try work(report)) }
            catch { state = .failed(error.localizedDescription) }

            await MainActor.run {
                cleanup()
                self.update(job.id) { $0.state = state; $0.progress = 1 }
                if case .done(let url) = state, SharedSettings.shared.revealInFinder {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                if case .failed(let message) = state { Self.showError(message, title: title) }
                self.finishIfIdle()
            }
        }
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func finishIfIdle() {
        if isIdle { onIdle?() }
    }

    private static func showError(_ message: String, title: String) {
        let alert = NSAlert()
        alert.messageText = "“\(title)”处理失败"
        alert.informativeText = message
        alert.runModal()
    }
}

/// 解压加密压缩包时询问密码。
@MainActor
enum PasswordPrompt {
    static func ask(for archive: URL) -> String? {
        let alert = NSAlert()
        alert.messageText = "“\(archive.lastPathComponent)”需要密码"
        alert.addButton(withTitle: "解压")
        alert.addButton(withTitle: "取消")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
