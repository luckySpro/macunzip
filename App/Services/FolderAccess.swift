import AppKit

/// 沙盒下的目录访问：首次启动授权个人文件夹并存书签，
/// 之后对任意位置的读写都先看已有书签，不够再弹面板请用户授权该目录。
@MainActor
enum FolderAccess {
    private static let homeBookmarkKey = "homeBookmark"
    private static var extraBookmarksKey: String { "extraBookmarks" }

    static var homeURL: URL {
        // 沙盒内 homeDirectoryForCurrentUser 指向容器，这里取真实的个人文件夹
        URL(fileURLWithPath: "/Users/\(NSUserName())", isDirectory: true)
    }

    static var hasHomeAccess: Bool { resolve(SharedSettings.shared.defaults.data(forKey: homeBookmarkKey)) != nil }

    /// 首次启动时请用户授权个人文件夹。
    @discardableResult
    static func requestHomeAccess() -> Bool {
        guard let url = pickFolder(at: homeURL, message: "请授权 MacUnZip 访问你的个人文件夹，这样双击压缩包就能直接在原位置解压。", prompt: "授权")
        else { return false }
        store(url, key: homeBookmarkKey)
        return true
    }

    /// 开始访问包含 `url` 的目录；返回结束访问的闭包。拿不到权限时返回 nil。
    static func beginAccess(toFolder url: URL) -> (() -> Void)? {
        let path = url.standardizedFileURL.path
        for scoped in allGrantedFolders() where path.hasPrefix(scoped.standardizedFileURL.path) {
            if scoped.startAccessingSecurityScopedResource() {
                return { scoped.stopAccessingSecurityScopedResource() }
            }
        }
        // 没有书签：请用户授权这个目录（例如外接硬盘），并记住它。
        guard let picked = pickFolder(at: url, message: "MacUnZip 需要访问“\(url.lastPathComponent)”才能在这里写入文件。", prompt: "授权")
        else { return nil }
        var extras = SharedSettings.shared.defaults.array(forKey: extraBookmarksKey) as? [Data] ?? []
        if let data = try? picked.bookmarkData(options: .withSecurityScope) { extras.append(data) }
        SharedSettings.shared.defaults.set(extras, forKey: extraBookmarksKey)
        _ = picked.startAccessingSecurityScopedResource()
        return { picked.stopAccessingSecurityScopedResource() }
    }

    static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope)
    }

    static func resolve(_ data: Data?) -> URL? {
        guard let data else { return nil }
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
    }

    static func pickFolder(at url: URL? = nil, message: String, prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.message = message
        panel.prompt = prompt
        panel.directoryURL = url
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func allGrantedFolders() -> [URL] {
        let defaults = SharedSettings.shared.defaults
        let datas = [defaults.data(forKey: homeBookmarkKey)].compactMap { $0 }
            + (defaults.array(forKey: extraBookmarksKey) as? [Data] ?? [])
            + SharedSettings.shared.favorites.compactMap(\.bookmark)
        return datas.compactMap(resolve)
    }

    private static func store(_ url: URL, key: String) {
        SharedSettings.shared.defaults.set(bookmark(for: url), forKey: key)
    }
}
