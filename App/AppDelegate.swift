import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var compressPanels: [NSPanel] = []
    private var previewWindows: [NSWindow] = []
    /// 本次启动是否只是为了处理双击 / 右键请求（不需要显示主窗口）。
    private var launchedForWork = false
    private var finishedLaunching = false

    // MARK: 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        finishedLaunching = true
        JobQueue.shared.onIdle = { [weak self] in self?.quitIfBackgroundOnly() }
        if !SharedSettings.shared.onboarded || !launchedForWork {
            showMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        JobQueue.shared.isIdle
    }

    // MARK: 打开文件与 URL

    /// 双击压缩包（文件 URL）或访达扩展唤起（macunzip://）都会走到这里。
    func application(_ application: NSApplication, open urls: [URL]) {
        if !finishedLaunching { launchedForWork = true }

        let fileURLs = urls.filter(\.isFileURL)
        for url in urls where url.scheme == "macunzip" {
            if let request = FinderRequest.take(id: url.lastPathComponent) { handle(request) }
        }
        guard !fileURLs.isEmpty else { return }

        let settings = SharedSettings.shared
        if settings.onboarded && settings.doubleClickBehavior == .extractInPlace {
            JobQueue.shared.extract(fileURLs)
        } else if !settings.onboarded {
            showMainWindow()
            MainModel.shared.pending = fileURLs
        } else {
            // “打开主界面”模式：每个压缩包打开一个内容预览窗口
            fileURLs.filter(ArchiveFormat.isArchive).forEach { showPreview(for: $0) }
        }
    }

    private func handle(_ request: FinderRequest) {
        let urls = request.urls
        switch request.action {
        case .quickCompress:
            JobQueue.shared.compress(urls, options: SharedSettings.shared.compressDefaults, password: nil)
        case .compress:
            showCompressPanel(for: urls)
        case .extractHere:
            JobQueue.shared.extract(urls)
        case .preview:
            urls.forEach { showPreview(for: $0) }
        case .extractTo:
            if let folder = FolderAccess.pickFolder(message: "选择解压位置", prompt: "解压到这里") {
                JobQueue.shared.extract(urls, to: folder)
            } else {
                quitIfBackgroundOnly()
            }
        }
    }

    // MARK: 窗口

    func showMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
                                  styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: MainView().environmentObject(MainModel.shared)
                .environmentObject(JobQueue.shared).themed())
            window.center()
            window.setFrameAutosaveName("MainWindow")
            mainWindow = window
        }
        launchedForWork = false
        NSApp.setActivationPolicy(.regular)
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showCompressPanel(for items: [URL]) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                            styleMask: [.titled, .closable, .fullSizeContentView],
                            backing: .buffered, defer: false)
        panel.title = items.count == 1 ? "压缩“\(items[0].lastPathComponent)”" : "压缩 \(items.count) 项"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: CompressPanel(items: items) { [weak self, weak panel] in
            panel?.close()
            if let panel { self?.compressPanels.removeAll { $0 === panel } }
            self?.quitIfBackgroundOnly()
        }.themed())
        panel.center()
        compressPanels.append(panel)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showPreview(for archive: URL) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = archive.lastPathComponent
        window.representedURL = archive
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreviewView(model: PreviewModel(archive: archive)) { [weak window] in
            window?.close()
        }.themed())
        window.center()
        previewWindows.append(window)
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self, weak window] _ in
            Task { @MainActor in
                self?.previewWindows.removeAll { $0 === window }
                // 关闭动画结束后窗口才算不可见
                try? await Task.sleep(nanoseconds: 300_000_000)
                self?.quitIfBackgroundOnly()
            }
        }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 只为后台任务启动、任务都结束且没有窗口时退出，保持“用完即走”。
    private func quitIfBackgroundOnly() {
        let hasWindows = NSApp.windows.contains { $0.isVisible }
        if launchedForWork && JobQueue.shared.isIdle && !hasWindows && !SharedSettings.shared.showMenuBar {
            NSApp.terminate(nil)
        }
    }
}
