import SwiftUI

@main
struct MacUnZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showMenuBar", store: SharedSettings.shared.defaults) private var showMenuBar = false

    var body: some Scene {
        // 主窗口由 AppDelegate 管理，这样双击压缩包时可以完全不出现窗口。
        Settings {
            SettingsView().themed()
        }

        // 方案 C：菜单栏常驻入口，在设置里开启
        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environmentObject(MainModel.shared)
                .environmentObject(JobQueue.shared)
                .themed()
        } label: {
            Image(systemName: "doc.zipper")
        }
        .menuBarExtraStyle(.window)
    }
}
