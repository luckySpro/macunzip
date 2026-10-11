import SwiftUI
import UniformTypeIdentifiers

/// 方案 A：单窗口工具台。上方切换解压 / 压缩，中间拖放区，下方可点击的常用目录。
struct MainView: View {
    @EnvironmentObject private var model: MainModel
    @EnvironmentObject private var queue: JobQueue
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            dropZone

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionLabel(model.mode == .extract ? "解压到" : "保存到")
                    Spacer()
                    Text("右键可设为默认").font(.caption2).foregroundStyle(.tertiary)
                }
                FolderChips()
            }

            if model.mode == .extract {
                HStack(spacing: 18) {
                    SettingToggle("完成后在访达中显示", get: { SharedSettings.shared.revealInFinder },
                                  set: { SharedSettings.shared.revealInFinder = $0 })
                    SettingToggle("解压后移到废纸篓", get: { SharedSettings.shared.trashArchiveAfterExtract },
                                  set: { SharedSettings.shared.trashArchiveAfterExtract = $0 })
                }
                .foregroundStyle(.secondary)
            }

            if !queue.jobs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("最近")
                    VStack(spacing: 0) {
                        ForEach(Array(queue.jobs.prefix(4).enumerated()), id: \.element.id) { index, job in
                            if index > 0 { Divider().padding(.leading, 34) }
                            JobRow(job: job).padding(.horizontal, 12)
                        }
                    }
                    .card(radius: 10)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 20)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeInOut(duration: 0.2), value: model.mode)
        .sheet(isPresented: $model.showOnboarding) { OnboardingView() }
        .onChange(of: model.pending) { pending in
            guard !pending.isEmpty, !model.showOnboarding else { return }
            model.mode = .extract
        }
    }

    /// 标题栏区域：左侧留给红绿灯，中间是模式切换。
    private var header: some View {
        ModeSwitch(selection: $model.mode, items: MainModel.Mode.allCases,
                   title: { $0.rawValue },
                   icon: { $0 == .extract ? "arrow.down.doc" : "doc.zipper" })
            .frame(maxWidth: .infinity)
    }

    private var dropZone: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(Theme.accent.opacity(dropTargeted ? 0.22 : 0.12)).frame(width: 64, height: 64)
                Image(systemName: model.mode == .extract ? "archivebox.fill" : "doc.zipper")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(Theme.accent.gradient)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(dropTargeted ? 1.08 : 1)

            if model.pending.isEmpty {
                VStack(spacing: 3) {
                    Text(model.mode == .extract ? "将压缩包拖到这里" : "将要压缩的文件拖到这里")
                        .font(.headline)
                    Text("或").font(.caption).foregroundStyle(.tertiary)
                }
                Button("选择文件…") { model.chooseFiles() }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
            } else {
                Text("\(model.pending.count) 个压缩包待解压").font(.headline)
                HStack(spacing: 8) {
                    Button("预览内容…") {
                        model.pending.forEach { (NSApp.delegate as? AppDelegate)?.showPreview(for: $0) }
                        model.pending = []
                    }
                    .controlSize(.large)
                    Button("解压到所选位置") {
                        model.handle(model.pending, folderID: model.selectedFolderID)
                        model.pending = []
                    }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            if model.mode == .extract {
                Text("ZIP · RAR · 7Z · TAR · GZ · XZ · ZST · ISO")
                    .font(.system(size: 10, weight: .medium)).tracking(0.8)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(dropTargeted ? AnyShapeStyle(Theme.accent.opacity(0.10)) : AnyShapeStyle(.background.opacity(0.55))))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(dropTargeted ? Theme.accent : Color.primary.opacity(0.12),
                          style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1.2, dash: [6, 5])))
        .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: dropTargeted)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            loadURLs(providers) { model.handle($0, folderID: model.selectedFolderID) }
            return true
        }
    }
}

/// 常用目录芯片：单击选中，拖文件到芯片上直接处理，右键设为默认。
struct FolderChips: View {
    @EnvironmentObject private var model: MainModel

    var body: some View {
        FlowLayout(spacing: 6) {
            FolderChip(title: "原位置", systemImage: "arrow.uturn.down.circle", folderID: nil)
                .contextMenu { Button("设为默认位置") { model.defaultFolderID = nil } }
            ForEach(model.favorites) { folder in
                FolderChip(title: folder.name, systemImage: "folder", folderID: folder.id)
                    .contextMenu {
                        Button("设为默认位置") { model.defaultFolderID = folder.id }
                        Button("在访达中显示") { NSWorkspace.shared.open(URL(fileURLWithPath: folder.path)) }
                        Divider()
                        Button("从常用目录移除", role: .destructive) { model.remove(folder) }
                    }
            }
            Button { model.addFavorite() } label: {
                Label("添加", systemImage: "plus").font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 12).frame(height: 30)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

struct FolderChip: View {
    @EnvironmentObject private var model: MainModel
    let title: String
    let systemImage: String
    let folderID: UUID?
    @State private var targeted = false

    private var isSelected: Bool { model.selectedFolderID == folderID }
    private var isDefault: Bool { model.defaultFolderID == folderID }

    var body: some View {
        Button { model.selectedFolderID = folderID } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? systemImage + ".fill" : systemImage)
                    .foregroundStyle(isSelected ? Color.white : Theme.accent)
                Text(title).fontWeight(isSelected ? .semibold : .regular)
                if isDefault {
                    Image(systemName: "star.fill").font(.system(size: 8))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.orange)
                }
            }
            .font(.callout)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(isSelected ? AnyShapeStyle(Theme.accent.gradient)
                                       : AnyShapeStyle(targeted ? Theme.accent.opacity(0.18) : Color.primary.opacity(0.06))))
            .overlay(Capsule().strokeBorder(targeted ? Theme.accent : .clear, lineWidth: 1.5))
            .shadow(color: isSelected ? Theme.accent.opacity(0.3) : .clear, radius: 4, y: 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadURLs(providers) { model.handle($0, folderID: folderID) }
            return true
        }
        .help(isDefault ? "默认位置" : "右键可设为默认位置")
    }
}

struct JobRow: View {
    let job: Job
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon).foregroundStyle(iconColor).frame(width: 16)
                Text(job.title).lineLimit(1).truncationMode(.middle)
                Spacer()
                switch job.state {
                case .running: Text("\(Int(job.progress * 100))%").foregroundStyle(.secondary).monospacedDigit()
                case .done(let url):
                    Button("在访达中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        .buttonStyle(.link).font(.caption)
                case .failed: Text("失败").foregroundStyle(.red)
                }
            }
            if job.state == .running { ProgressView(value: job.progress).controlSize(.small) }
        }
        .font(.callout)
        .padding(.vertical, 8)
    }

    private var icon: String {
        switch job.state {
        case .running: return "arrow.triangle.2.circlepath"
        case .done: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
    private var iconColor: Color {
        switch job.state {
        case .running: return Theme.accent
        case .done: return .green
        case .failed: return .red
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }
}

/// 直接读写 SharedSettings 的复选框。
struct SettingToggle: View {
    let title: String
    let get: () -> Bool
    let set: (Bool) -> Void
    @State private var value = false

    init(_ title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
        self.title = title; self.get = get; self.set = set
    }

    var body: some View {
        Toggle(title, isOn: $value)
            .toggleStyle(.checkbox)
            .font(.callout)
            .onAppear { value = get() }
            .onChange(of: value) { set($0) }
    }
}

/// 简单的自动换行布局，用于目录芯片。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 从拖放数据里取出文件 URL。
func loadURLs(_ providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url { lock.lock(); urls.append(url); lock.unlock() }
            group.leave()
        }
    }
    group.notify(queue: .main) { Task { @MainActor in completion(urls) } }
}
