import Cocoa
import FinderSync

/// 访达右键菜单。扩展本身不做压缩：把选中的文件写成请求交给主程序，
/// 主程序负责权限、进度和错误提示。
final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // 监听整个磁盘，任何位置右键都能看到菜单
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForItems,
              let selected = FIFinderSyncController.default().selectedItemURLs(), !selected.isEmpty
        else { return nil }

        let defaults = SharedSettings.shared.compressDefaults
        let submenu = NSMenu(title: "MacUnZip")
        submenu.addItem(item("快速压缩为 \(defaults.format.displayName)", #selector(quickCompress(_:))))
        submenu.addItem(item("压缩…", #selector(compress(_:))))

        if selected.allSatisfy(ArchiveFormat.isArchive) {
            submenu.addItem(.separator())
            submenu.addItem(item("解压到此处", #selector(extractHere(_:))))
            submenu.addItem(item("解压到…", #selector(extractTo(_:))))
            if selected.count == 1 { submenu.addItem(item("预览内容…", #selector(preview(_:)))) }
        }

        let menu = NSMenu(title: "")
        let root = NSMenuItem(title: "MacUnZip", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "doc.zipper", accessibilityDescription: nil)
        root.submenu = submenu
        menu.addItem(root)
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func quickCompress(_ sender: NSMenuItem) { send(.quickCompress) }
    @objc private func compress(_ sender: NSMenuItem) { send(.compress) }
    @objc private func extractHere(_ sender: NSMenuItem) { send(.extractHere) }
    @objc private func extractTo(_ sender: NSMenuItem) { send(.extractTo) }
    @objc private func preview(_ sender: NSMenuItem) { send(.preview) }

    private func send(_ action: FinderRequest.Action) {
        guard let urls = FIFinderSyncController.default().selectedItemURLs(), !urls.isEmpty else { return }
        let request = FinderRequest(action: action, paths: urls.map(\.path))
        if let launchURL = try? request.write() {
            NSWorkspace.shared.open(launchURL)
        }
    }
}
