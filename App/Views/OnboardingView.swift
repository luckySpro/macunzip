import SwiftUI

/// 首次启动：选择双击行为、设为默认打开方式、授权个人文件夹、引导开启右键菜单。
struct OnboardingView: View {
    @EnvironmentObject private var model: MainModel
    @State private var behavior: DoubleClickBehavior = .extractInPlace
    @State private var makeDefault = true
    @State private var homeGranted = FolderAccess.hasHomeAccess
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("双击压缩包时…").font(.headline)
                    Text("随时可以在“设置”中更改").font(.caption).foregroundStyle(.secondary)
                }
            }

            OptionCard(title: "直接解压到同一目录", detail: "不打开窗口，完成后在访达中选中解压出的文件夹",
                       selected: behavior == .extractInPlace) { behavior = .extractInPlace }
            OptionCard(title: "打开 MacUnZip 主界面", detail: "先选择目标位置，再解压",
                       selected: behavior == .openWindow) { behavior = .openWindow }

            Toggle("将 MacUnZip 设为 zip、rar、7z 等格式的默认打开方式", isOn: $makeDefault)
                .toggleStyle(.checkbox)

            HStack(spacing: 10) {
                Image(systemName: homeGranted ? "checkmark.circle.fill" : "folder")
                    .foregroundStyle(homeGranted ? Color.green : Theme.accent).font(.title3)
                Text(homeGranted ? "已获得个人文件夹的访问权限。"
                                 : "要在压缩包所在位置解压，需要授权访问你的个人文件夹（一次即可）。")
                    .font(.callout).fixedSize(horizontal: false, vertical: true)
                Spacer()
                if !homeGranted { Button("授权…") { homeGranted = FolderAccess.requestHomeAccess() } }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color(nsColor: .controlBackgroundColor)))

            Text("提示：在“系统设置 › 通用 › 登录项与扩展”中启用“MacUnZip 右键菜单”，即可在访达里右键压缩。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            HStack {
                Button("打开扩展设置") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                }
                Spacer()
                Button("稍后") { finish(applyDefault: false) }
                Button("完成") { finish(applyDefault: makeDefault) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
            }
        }
        .padding(22)
        .frame(width: 470)
    }

    private func finish(applyDefault: Bool) {
        let settings = SharedSettings.shared
        settings.doubleClickBehavior = behavior
        settings.onboarded = true
        guard applyDefault else { close(); return }
        working = true
        Task {
            _ = await DefaultHandler.makeDefault()
            working = false
            close()
        }
    }

    private func close() {
        model.showOnboarding = false
        // 首次启动时如果是双击压缩包进来的，现在按刚选的方式处理它
        if !model.pending.isEmpty && behavior == .extractInPlace {
            JobQueue.shared.extract(model.pending)
            model.pending = []
        }
    }
}

private struct OptionCard: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).fontWeight(.semibold)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.accent.opacity(0.1) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Theme.accent : Color(nsColor: .separatorColor),
                                                                    lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }
}
