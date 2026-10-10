import SwiftUI

/// 方案 C：菜单栏弹出的小面板。常用目录做成磁贴，拖文件到磁贴上即执行。
struct MenuBarView: View {
    @EnvironmentObject private var model: MainModel
    @EnvironmentObject private var queue: JobQueue
    @State private var dropTargeted = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("", selection: $model.mode) {
                    ForEach(MainModel.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 120)
                Spacer()
                Text("拖到磁贴即执行").font(.caption).foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "doc.zipper").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("拖入文件").fontWeight(.semibold)
                    Text("默认\(model.mode == .extract ? "解压" : "保存")到 \(defaultName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 9).fill(dropTargeted ? Color.accentColor.opacity(0.12) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(dropTargeted ? Color.accentColor : Color(nsColor: .separatorColor),
                                                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                loadURLs(providers) { model.handle($0, folderID: model.defaultFolderID) }
                return true
            }

            LazyVGrid(columns: columns, spacing: 6) {
                Tile(title: "原位置", systemImage: "arrow.down.right.and.arrow.up.left", folderID: nil)
                ForEach(model.favorites.prefix(8)) { folder in
                    Tile(title: folder.name, systemImage: "folder", folderID: folder.id)
                }
                Button { model.addFavorite() } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus").font(.title3)
                        Text("添加").font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let job = queue.jobs.first { JobRow(job: job) }

            Divider()
            HStack {
                Button("打开主窗口") { (NSApp.delegate as? AppDelegate)?.showMainWindow() }
                Spacer()
                Button("设置…") {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                Button("退出") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(12)
        .frame(width: 330)
    }

    private var defaultName: String {
        model.favorites.first { $0.id == model.defaultFolderID }?.name ?? "原位置"
    }
}

private struct Tile: View {
    @EnvironmentObject private var model: MainModel
    let title: String
    let systemImage: String
    let folderID: UUID?
    @State private var targeted = false

    var body: some View {
        let isDefault = model.defaultFolderID == folderID
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.title3).foregroundStyle(Color.accentColor)
            Text(title).font(.caption).lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(RoundedRectangle(cornerRadius: 9).fill(isDefault || targeted ? Color.accentColor.opacity(0.12) : Color(nsColor: .quaternaryLabelColor).opacity(0.4)))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(isDefault ? Color.accentColor : .clear, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) {
            if isDefault { Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.orange).padding(5) }
        }
        .onTapGesture { model.defaultFolderID = folderID }
        .contextMenu { Button("设为默认位置") { model.defaultFolderID = folderID } }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            loadURLs(providers) { model.handle($0, folderID: folderID) }
            return true
        }
        .help("单击设为默认；拖文件到这里直接处理")
    }
}
