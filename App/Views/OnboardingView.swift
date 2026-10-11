import SwiftUI

/// 首次启动：选择双击行为、设为默认打开方式、授权个人文件夹、引导开启右键菜单。
struct OnboardingView: View {
    @EnvironmentObject private var model: MainModel
    @State private var behavior: DoubleClickBehavior = .extractInPlace
    @State private var makeDefault = true
    @State private var homeGranted = FolderAccess.hasHomeAccess
    @State private var working = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                    .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("欢迎使用 MacUnZip").font(.title2.weight(.bold))
                    Text("先做三项设置，之后都可以在“设置”里更改").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)

            // 与设置页一致：分组卡片样式
            Form {
                Section {
                    Picker("双击压缩包时", selection: $behavior) {
                        Text("直接解压").tag(DoubleClickBehavior.extractInPlace)
                        Text("打开主界面").tag(DoubleClickBehavior.openWindow)
                    }
                    Toggle("设为 zip、rar、7z 等格式的默认打开方式", isOn: $makeDefault)
                } header: {
                    Text("通用")
                } footer: {
                    Text(behavior == .extractInPlace
                         ? "双击后不打开窗口，解压到默认位置，完成后在访达中选中结果。"
                         : "双击后打开内容预览，选好文件和位置再解压。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("权限") {
                    LabeledContent("个人文件夹") {
                        if homeGranted {
                            Label("已授权", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.accent)
                        } else {
                            Button("授权…") { homeGranted = FolderAccess.requestHomeAccess() }
                        }
                    }
                    LabeledContent("访达右键菜单") {
                        Button("打开扩展设置") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences")!)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("稍后") { finish(applyDefault: false) }
                    .controlSize(.large)
                Button("完成") { finish(applyDefault: makeDefault) }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 18)
        }
        .frame(width: 500, height: 420)
        .themed()
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
