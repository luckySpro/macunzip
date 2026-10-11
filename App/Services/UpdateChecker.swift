import AppKit
import SwiftUI

/// 版本检查与强制升级。
///
/// 升级清单 `update.json` 放在仓库默认分支，只有仓库所有者能修改，通过 HTTPS 从 GitHub 读取：
/// `{"latest": "0.2.0", "minimum": "0.1.0", "url": "https://…", "notes": "…"}`
/// 当前版本低于 `minimum` 时进入强制升级：弹出不可关闭的升级窗口，并拒绝新的解压 / 压缩任务。
/// 已知的最低版本缓存在本地，只升不降；断网时沿用缓存，从未拿到清单就不拦截，离线照常使用。
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Manifest: Codable, Equatable {
        var latest: String
        var minimum: String
        var url: String
        var notes: String?
    }

    static let manifestURL = URL(string: "https://raw.githubusercontent.com/luckySpro/macunzip/HEAD/update.json")!
    private static let cacheKey = "updateManifest"

    @Published private(set) var manifest: Manifest?
    private var window: NSWindow?
    private var timer: Timer?

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    private init() {
        manifest = SharedSettings.shared.defaults.data(forKey: Self.cacheKey)
            .flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
    }

    /// 当前版本是否已低于最低支持版本。
    var isRequired: Bool {
        guard let manifest else { return false }
        return Self.compare(currentVersion, manifest.minimum) == .orderedAscending
    }

    var hasOptionalUpdate: Bool {
        guard let manifest, !isRequired else { return false }
        return Self.compare(currentVersion, manifest.latest) == .orderedAscending
    }

    /// 启动时调用：先按缓存拦截，再联网刷新，之后每 6 小时检查一次。
    func start() {
        if isRequired { presentRequired() }
        Task { await refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            Task { @MainActor in await UpdateChecker.shared.refresh() }
        }
    }

    func refresh() async {
        var request = URLRequest(url: Self.manifestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("MacUnZip/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              var fetched = try? JSONDecoder().decode(Manifest.self, from: data),
              let link = URL(string: fetched.url), link.scheme == "https" else { return }
        // 最低版本只升不降，防止旧缓存或被回滚的清单解除强制升级
        if let known = manifest, Self.compare(fetched.minimum, known.minimum) == .orderedAscending {
            fetched.minimum = known.minimum
        }
        manifest = fetched
        SharedSettings.shared.defaults.set(try? JSONEncoder().encode(fetched), forKey: Self.cacheKey)
        if isRequired { presentRequired() }
    }

    /// 任务入口调用：需要强制升级时弹窗并返回 false。
    func allowsWork() -> Bool {
        guard isRequired else { return true }
        presentRequired()
        return false
    }

    func presentRequired() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window { window.makeKeyAndOrderFront(nil); return }
        // 没有关闭和最小化按钮，Esc 也关不掉；只能升级或退出
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 300),
                              styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.contentViewController = NSHostingController(rootView: RequiredUpdateView(checker: self).themed())
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func openDownload() {
        if let link = manifest.flatMap({ URL(string: $0.url) }) { NSWorkspace.shared.open(link) }
    }

    /// 按数字逐段比较版本号（1.10.0 > 1.9.0），不用字符串排序。
    nonisolated static func compare(_ a: String, _ b: String) -> ComparisonResult {
        func parts(_ s: String) -> [Int] {
            s.split(separator: "-").first.map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}

private struct RequiredUpdateView: View {
    @ObservedObject var checker: UpdateChecker

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            Text("需要升级 MacUnZip").font(.title2.weight(.bold))
            Text("当前版本 \(checker.currentVersion) 已停止支持，请升级到 \(checker.manifest?.latest ?? "最新版本") 后继续使用。")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if let notes = checker.manifest?.notes, !notes.isEmpty {
                ScrollView {
                    Text(notes).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 90)
                .padding(10)
                .card(radius: 10)
            }
            HStack {
                Button("退出") { NSApp.terminate(nil) }.controlSize(.large)
                Spacer()
                Button("立即升级") { checker.openDownload() }
                    .controlSize(.large).buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}
