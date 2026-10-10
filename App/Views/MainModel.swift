import SwiftUI

/// 主窗口的状态：当前模式、常用目录、默认目录。
@MainActor
final class MainModel: ObservableObject {
    static let shared = MainModel()

    enum Mode: String, CaseIterable, Identifiable {
        case extract = "解压", compress = "压缩"
        var id: String { rawValue }
    }

    @Published var mode: Mode = .extract
    @Published var favorites: [FavoriteFolder] = SharedSettings.shared.favorites {
        didSet { SharedSettings.shared.favorites = favorites }
    }
    /// nil 表示“原位置”。
    @Published var defaultFolderID: UUID? = SharedSettings.shared.defaultExtractFolderID {
        didSet { SharedSettings.shared.defaultExtractFolderID = defaultFolderID }
    }
    /// 当前选中的目标；默认跟随 defaultFolderID。
    @Published var selectedFolderID: UUID? = SharedSettings.shared.defaultExtractFolderID
    @Published var showOnboarding = !SharedSettings.shared.onboarded
    /// 以“打开主界面”方式双击进来的压缩包，等用户选目标后处理。
    @Published var pending: [URL] = []

    init() {
        if favorites.isEmpty {
            favorites = Self.suggestedFavorites()
            SharedSettings.shared.favorites = favorites  // init 中不会触发 didSet
        }
    }

    func addFavorite() {
        guard let url = FolderAccess.pickFolder(message: "选择要加入常用目录的文件夹", prompt: "添加") else { return }
        favorites.append(FavoriteFolder(name: url.lastPathComponent, path: url.path, bookmark: FolderAccess.bookmark(for: url)))
    }

    func remove(_ folder: FavoriteFolder) {
        favorites.removeAll { $0.id == folder.id }
        if defaultFolderID == folder.id { defaultFolderID = nil }
        if selectedFolderID == folder.id { selectedFolderID = defaultFolderID }
    }

    func destinationURL(for id: UUID?) -> URL? {
        guard let id, let folder = favorites.first(where: { $0.id == id }) else { return nil }
        return FolderAccess.resolve(folder.bookmark) ?? URL(fileURLWithPath: folder.path)
    }

    /// 处理拖入或选择的文件。`folderID` 为 nil 表示原位置。
    func handle(_ urls: [URL], folderID: UUID?) {
        let destination = destinationURL(for: folderID)
        switch mode {
        case .extract:
            JobQueue.shared.extract(urls.filter(ArchiveFormat.isArchive), to: destination)
        case .compress:
            var options = SharedSettings.shared.compressDefaults
            if let folderID { options.destination = .favorite(folderID) } else { options.destination = .sameFolder }
            JobQueue.shared.compress(urls, options: options, password: nil)
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = mode == .compress
        panel.message = mode == .extract ? "选择要解压的压缩包" : "选择要压缩的文件或文件夹"
        if panel.runModal() == .OK { handle(panel.urls, folderID: selectedFolderID) }
    }

    private static func suggestedFavorites() -> [FavoriteFolder] {
        let home = FolderAccess.homeURL
        return [("下载", "Downloads"), ("桌面", "Desktop"), ("文稿", "Documents")].map {
            FavoriteFolder(name: $0.0, path: home.appendingPathComponent($0.1).path)
        }
    }
}
