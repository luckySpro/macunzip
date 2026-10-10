import SwiftUI

@main
struct MacUnZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 主窗口由 AppDelegate 管理，这样双击压缩包时可以完全不出现窗口。
        Settings {
            SettingsView()
        }
    }
}
