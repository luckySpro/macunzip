import SwiftUI
import UniformTypeIdentifiers

/// 方案 A：单窗口工具台。上方切换解压 / 压缩，中间拖放区，下方可点击的常用目录。
struct MainView: View {
    @EnvironmentObject private var model: MainModel
    @EnvironmentObject private var queue: JobQueue
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("", selection: $model.mode) {
                ForEach(MainModel.Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 140)
            .frame(maxWidth: .infinity)

            dropZone

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(model.mode == .extract ? "解压到" : "保存到")
                FolderChips()
            }

            if model.mode == .extract {
                HStack(spacing: 16) {
                    SettingToggle("完成后在访达中显示", get: { SharedSettings.shared.revealInFinder },
                                  set: { SharedSettings.shared.revealInFinder = $0 })
                    SettingToggle("解压后移到废纸篓", get: { SharedSettings.shared.trashArchiveAfterExtract },
                                  set: { SharedSettings.shared.trashArchiveAfterExtract = $0 })
                }
            }

            if !queue.jobs.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("最近")
                    ForEach(queue.jobs.prefix(4)) { JobRow(job: $0) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $model.showOnboarding) { OnboardingView() }
        .onChange(of: model.pending) { pending in
            guard !pending.isEmpty, !model.showOnboarding else { return }
            model.mode = .extract
        }
    }

    private var dropZone: some View {
        VStack(spacing: 8) {
            Image(systemName: model.mode == .extract ? "archivebox" : "doc.zipper")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            if model.pending.isEmpty {
                Text(model.mode == .extract ? "拖入压缩包" : "拖入要压缩的文件").fontWeight(.semibold)
                Button("选择文件…") { model.chooseFiles() }
            } else {
                Text("\(model.pending.count) 个压缩包待解压").fontWeight(.semibold)
                Button("解压到所选位置") {
                    model.handle(model.pending, folderID: model.selectedFolderID)
                    model.pending = []
                }
                .keyboardShortcut(.defaultAction)
            }
            if model.mode == .extract {
                Text("zip · rar · 7z · tar · gz · xz · zst · iso").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(RoundedRectangle(cornerRadius: 10).fill(dropTargeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(dropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                                                 style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
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
            FolderChip(title: "原位置", systemImage: "arrow.down.right.and.arrow.up.left", folderID: nil)
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
                Label("添加", systemImage: "plus").font(.callout)
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 8)
            .frame(height: 26)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color(nsColor: .separatorColor)))
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
            HStack(spacing: 5) {
                if isDefault { Image(systemName: "star.fill").foregroundStyle(.orange).font(.caption2) }
                Image(systemName: systemImage).foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(title)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7).fill(isSelected || targeted ? Color.accentColor.opacity(0.14) : Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(isSelected ? Color.accentColor : .clear))
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
                Image(systemName: "doc.zipper").foregroundStyle(.secondary)
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
        .padding(.vertical, 6)
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
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
