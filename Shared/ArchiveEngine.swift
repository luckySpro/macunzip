import Foundation
import CArchive

enum ArchiveError: LocalizedError {
    case passwordRequired
    case wrongPassword
    case libarchive(String)

    var errorDescription: String? {
        switch self {
        case .passwordRequired: return "这个压缩包有密码。"
        case .wrongPassword: return "密码不正确。"
        case .libarchive(let message): return message
        }
    }
}

/// libarchive 的薄封装：解压任意支持的格式，压缩为 zip / 7z / tar.gz / tar.zst。
/// 所有方法都是同步阻塞的，请在后台线程调用。
enum ArchiveEngine {
    typealias Progress = (Double) -> Void

    // MARK: 解压

    /// 解压到 `parent` 目录下，返回最终生成的文件或文件夹。
    /// 只有一个顶层项目时直接放出该项目，否则放进以压缩包命名的文件夹，避免“文件撒一地”。
    @discardableResult
    static func extract(_ archive: URL, into parent: URL, password: String? = nil,
                        progress: Progress? = nil) throws -> URL {
        let fm = FileManager.default
        let staging = parent.appendingPathComponent(".macunzip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }

        try extractRaw(archive, to: staging, password: password, progress: progress)

        let items = try fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent != "__MACOSX" }
        let result: URL
        if items.count == 1 {
            result = uniqueURL(parent.appendingPathComponent(items[0].lastPathComponent))
            try fm.moveItem(at: items[0], to: result)
        } else {
            result = uniqueURL(parent.appendingPathComponent(baseName(of: archive), isDirectory: true))
            try fm.createDirectory(at: result, withIntermediateDirectories: false)
            for item in items {
                try fm.moveItem(at: item, to: result.appendingPathComponent(item.lastPathComponent))
            }
        }
        return result
    }

    private static func extractRaw(_ archive: URL, to dest: URL, password: String?, progress: Progress?) throws {
        guard let reader = archive_read_new() else { throw ArchiveError.libarchive("无法初始化解压器") }
        defer { archive_read_free(reader) }
        archive_read_support_filter_all(reader)
        archive_read_support_format_all(reader)
        if let password, !password.isEmpty { archive_read_add_passphrase(reader, password) }

        guard archive_read_open_filename(reader, archive.path, 64 * 1024) == ARCHIVE_OK else {
            throw error(reader)
        }

        guard let writer = archive_write_disk_new() else { throw ArchiveError.libarchive("无法初始化写入器") }
        defer { archive_write_free(writer) }
        let flags = ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM
            | ARCHIVE_EXTRACT_SECURE_NODOTDOT | ARCHIVE_EXTRACT_SECURE_SYMLINKS
            | ARCHIVE_EXTRACT_SECURE_NOABSOLUTEPATHS
        archive_write_disk_set_options(writer, flags)
        archive_write_disk_set_standard_lookup(writer)

        let totalSize = Double((try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var entry: OpaquePointer?
        while true {
            let status = archive_read_next_header(reader, &entry)
            if status == ARCHIVE_EOF { break }
            guard status >= ARCHIVE_WARN, let entry else { throw error(reader) }

            if archive_entry_is_encrypted(entry) != 0, password?.isEmpty ?? true {
                throw ArchiveError.passwordRequired
            }
            guard let name = archive_entry_pathname(entry).map({ String(cString: $0) }) else { continue }
            archive_entry_set_pathname(entry, dest.appendingPathComponent(name).path)

            guard archive_write_header(writer, entry) >= ARCHIVE_WARN else { throw error(writer) }
            if archive_entry_size(entry) > 0 || archive_entry_size_is_set(entry) == 0 {
                try copyData(from: reader, to: writer, encrypted: archive_entry_is_encrypted(entry) != 0)
            }
            archive_write_finish_entry(writer)

            if totalSize > 0 {
                progress?(min(1, Double(archive_filter_bytes(reader, -1)) / totalSize))
            }
        }
        progress?(1)
    }

    private static func copyData(from reader: OpaquePointer, to writer: OpaquePointer, encrypted: Bool) throws {
        var buffer: UnsafeRawPointer?
        var size = 0
        var offset: la_int64_t = 0
        while true {
            let status = archive_read_data_block(reader, &buffer, &size, &offset)
            if status == ARCHIVE_EOF { return }
            guard status >= ARCHIVE_WARN else {
                throw encrypted ? ArchiveError.wrongPassword : error(reader)
            }
            guard archive_write_data_block(writer, buffer, size, offset) >= ARCHIVE_WARN else {
                throw error(writer)
            }
        }
    }

    /// 是否需要密码（只看到第一个加密条目即返回）。
    static func needsPassword(_ archive: URL) -> Bool {
        guard let reader = archive_read_new() else { return false }
        defer { archive_read_free(reader) }
        archive_read_support_filter_all(reader)
        archive_read_support_format_all(reader)
        guard archive_read_open_filename(reader, archive.path, 64 * 1024) == ARCHIVE_OK else { return false }
        var entry: OpaquePointer?
        while archive_read_next_header(reader, &entry) == ARCHIVE_OK, let entry {
            if archive_entry_is_encrypted(entry) != 0 { return true }
            archive_read_data_skip(reader)
        }
        return archive_read_has_encrypted_entries(reader) > 0
    }

    // MARK: 压缩

    static func compress(_ items: [URL], to output: URL, format: ArchiveFormat,
                         level: CompressionLevel, password: String? = nil,
                         excludeMacMetadata: Bool = true, progress: Progress? = nil) throws {
        guard let writer = archive_write_new() else { throw ArchiveError.libarchive("无法初始化压缩器") }
        defer { archive_write_free(writer) }

        switch format {
        case .zip:
            archive_write_set_format_zip(writer)
            archive_write_set_options(writer, level == .store
                ? "zip:compression=store"
                : "zip:compression=deflate,zip:compression-level=\(level.rawValue)")
            if let password, !password.isEmpty {
                archive_write_set_options(writer, "zip:encryption=aes256")
                archive_write_set_passphrase(writer, password)
            }
        case .sevenZip:
            archive_write_set_format_7zip(writer)
            archive_write_set_options(writer, level == .store
                ? "7zip:compression=store"
                : "7zip:compression=lzma2,7zip:compression-level=\(level.rawValue)")
        case .tarGz:
            archive_write_set_format_pax_restricted(writer)
            archive_write_add_filter_gzip(writer)
            archive_write_set_options(writer, "gzip:compression-level=\(max(1, level.rawValue))")
        case .tarZst:
            archive_write_set_format_pax_restricted(writer)
            archive_write_add_filter_zstd(writer)
            // zstd 档位范围更大，按 1/3/9/19 映射
            let zstdLevel = [0: 1, 1: 3, 6: 9, 9: 19][level.rawValue] ?? 3
            archive_write_set_options(writer, "zstd:compression-level=\(zstdLevel)")
        }

        guard archive_write_open_filename(writer, output.path) == ARCHIVE_OK else { throw error(writer) }

        let files = collect(items, excludeMacMetadata: excludeMacMetadata)
        let totalBytes = Double(files.reduce(0) { $0 + $1.size })
        var written = 0.0
        var buffer = [UInt8](repeating: 0, count: 256 * 1024)

        for file in files {
            guard let entry = archive_entry_new() else { continue }
            defer { archive_entry_free(entry) }
            archive_entry_set_pathname(entry, file.relativePath)
            archive_entry_set_perm(entry, mode_t(file.permissions))
            archive_entry_set_mtime(entry, time_t(file.modified.timeIntervalSince1970), 0)

            switch file.kind {
            case .directory:
                archive_entry_set_filetype(entry, UInt32(S_IFDIR))
            case .symlink(let target):
                archive_entry_set_filetype(entry, UInt32(S_IFLNK))
                archive_entry_set_symlink(entry, target)
            case .regular:
                archive_entry_set_filetype(entry, UInt32(S_IFREG))
                archive_entry_set_size(entry, la_int64_t(file.size))
            }
            guard archive_write_header(writer, entry) >= ARCHIVE_WARN else { throw error(writer) }

            if case .regular = file.kind, let handle = try? FileHandle(forReadingFrom: file.url) {
                defer { try? handle.close() }
                while true {
                    let count = buffer.withUnsafeMutableBytes { raw in
                        read(handle.fileDescriptor, raw.baseAddress, raw.count)
                    }
                    if count <= 0 { break }
                    let ok = buffer.withUnsafeBytes { archive_write_data(writer, $0.baseAddress, count) }
                    guard ok >= 0 else { throw error(writer) }
                    written += Double(count)
                    if totalBytes > 0 { progress?(written / totalBytes) }
                }
            }
        }
        guard archive_write_close(writer) == ARCHIVE_OK else { throw error(writer) }
        progress?(1)
    }

    private struct Item {
        enum Kind { case regular, directory, symlink(String) }
        var url: URL
        var relativePath: String
        var kind: Kind
        var size: Int
        var permissions: Int
        var modified: Date
    }

    private static func collect(_ roots: [URL], excludeMacMetadata: Bool) -> [Item] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]
        let fm = FileManager.default
        var result: [Item] = []

        func add(_ url: URL, relative: String) {
            let name = url.lastPathComponent
            if excludeMacMetadata && (name == ".DS_Store" || name.hasPrefix("._") || name == "__MACOSX") { return }
            let values = try? url.resourceValues(forKeys: Set(keys))
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let perms = (attrs?[.posixPermissions] as? Int) ?? 0o644
            let modified = values?.contentModificationDate ?? Date()

            if values?.isSymbolicLink == true, let target = try? fm.destinationOfSymbolicLink(atPath: url.path) {
                result.append(Item(url: url, relativePath: relative, kind: .symlink(target), size: 0, permissions: perms, modified: modified))
            } else if values?.isDirectory == true {
                result.append(Item(url: url, relativePath: relative + "/", kind: .directory, size: 0, permissions: perms, modified: modified))
                let children = (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: keys)) ?? []
                for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    add(child, relative: relative + "/" + child.lastPathComponent)
                }
            } else {
                result.append(Item(url: url, relativePath: relative, kind: .regular, size: values?.fileSize ?? 0, permissions: perms, modified: modified))
            }
        }

        for root in roots { add(root, relative: root.lastPathComponent) }
        return result
    }

    // MARK: 工具

    /// 压缩包名去掉所有压缩扩展名，例如 a.tar.gz → a。
    static func baseName(of url: URL) -> String {
        var name = url.deletingPathExtension().lastPathComponent
        if name.lowercased().hasSuffix(".tar") { name = String(name.dropLast(4)) }
        return name
    }

    /// 已存在同名项目时追加“ 2”“ 3”…
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let stem = url.deletingPathExtension().lastPathComponent
        for n in 2... {
            let name = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            let candidate = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return url
    }

    private static func error(_ archive: OpaquePointer) -> ArchiveError {
        let message = archive_error_string(archive).map { String(cString: $0) } ?? "未知错误"
        if message.localizedCaseInsensitiveContains("passphrase") || message.localizedCaseInsensitiveContains("password") {
            return .wrongPassword
        }
        return .libarchive(message)
    }
}
