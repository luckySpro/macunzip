import Foundation
import CUnRAR

/// 用官方 UnRAR 库处理 RAR（含加密 RAR、RAR5）。libarchive 无法解密 RAR，所以 RAR 一律走这里。
enum RarEngine {
    static func handles(_ archive: URL) -> Bool {
        archive.pathExtension.lowercased() == "rar"
    }

    /// 回调里需要的上下文：提供密码，并记录 UnRAR 是否索要过密码。
    private final class Context {
        let password: [wchar_t]?
        var askedForPassword = false
        init(password: String?) {
            self.password = password.flatMap { $0.isEmpty ? nil : wide($0) }
        }
    }

    private static let callback: UNRARCALLBACK = { message, userData, p1, p2 in
        guard message == UCM_NEEDPASSWORDW.rawValue, userData != 0,
              let raw = UnsafeMutableRawPointer(bitPattern: userData) else { return 1 }
        let context = Unmanaged<Context>.fromOpaque(raw).takeUnretainedValue()
        context.askedForPassword = true
        guard let password = context.password,
              let buffer = UnsafeMutablePointer<wchar_t>(bitPattern: p1), p2 > 0 else { return -1 }
        let count = min(password.count, Int(p2))  // password 已含结尾 0
        for i in 0..<count { buffer[i] = password[i] }
        buffer[Int(p2) - 1] = 0
        return 1
    }

    private static func open(_ archive: URL, mode: Int32, context: Context) throws -> (UnsafeMutableRawPointer, UInt32) {
        var path = wide(archive.path)
        var data = RAROpenArchiveDataEx()
        data.OpenMode = UInt32(mode)
        data.Callback = callback
        data.UserData = Int(bitPattern: Unmanaged.passUnretained(context).toOpaque())
        let handle = path.withUnsafeMutableBufferPointer { buffer -> UnsafeMutableRawPointer? in
            data.ArcNameW = buffer.baseAddress
            return RAROpenArchiveEx(&data)
        }
        guard let handle, data.OpenResult == UInt32(ERAR_SUCCESS) else {
            if let handle { RARCloseArchive(handle) }
            throw error(Int32(data.OpenResult), context: context)
        }
        return (handle, data.Flags)
    }

    static func extract(_ archive: URL, to dest: URL, password: String?, only selection: Set<String>?,
                        progress: ArchiveEngine.Progress?) throws {
        let context = Context(password: password)
        let (handle, _) = try open(archive, mode: RAR_OM_EXTRACT, context: context)
        defer { RARCloseArchive(handle) }

        let totalSize = Double((try? archive.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        var processed = 0.0
        var destPath = wide(dest.path)
        var header = RARHeaderDataEx()
        while true {
            let status = RARReadHeaderEx(handle, &header)
            if status == ERAR_END_ARCHIVE { break }
            guard status == ERAR_SUCCESS else { throw error(status, context: context) }

            let name = fileName(of: &header)
            let operation = ArchiveEngine.isSelected(name, in: selection) ? RAR_EXTRACT : RAR_SKIP
            let result = destPath.withUnsafeMutableBufferPointer {
                RARProcessFileW(handle, operation, $0.baseAddress, nil)
            }
            guard result == ERAR_SUCCESS else { throw error(result, context: context) }

            processed += Double(UInt64(header.PackSizeHigh) << 32 | UInt64(header.PackSize))
            if totalSize > 0 { progress?(min(1, processed / totalSize)) }
        }
        progress?(1)
    }

    static func list(_ archive: URL, password: String?) throws -> [ArchiveEngine.Entry] {
        let context = Context(password: password)
        let (handle, _) = try open(archive, mode: RAR_OM_LIST, context: context)
        defer { RARCloseArchive(handle) }

        var entries: [ArchiveEngine.Entry] = []
        var header = RARHeaderDataEx()
        while true {
            let status = RARReadHeaderEx(handle, &header)
            if status == ERAR_END_ARCHIVE { break }
            guard status == ERAR_SUCCESS else { throw error(status, context: context) }
            let size = Int64(UInt64(header.UnpSizeHigh) << 32 | UInt64(header.UnpSize))
            entries.append(.init(path: fileName(of: &header), size: size,
                                 isDirectory: header.Flags & UInt32(RHDF_DIRECTORY) != 0,
                                 modified: dosDate(header.FileTime)))
            RARProcessFileW(handle, RAR_SKIP, nil, nil)
        }
        return entries
    }

    static func needsPassword(_ archive: URL) -> Bool {
        let context = Context(password: nil)
        guard let opened = try? open(archive, mode: RAR_OM_LIST, context: context) else {
            return context.askedForPassword
        }
        let (handle, flags) = opened
        defer { RARCloseArchive(handle) }
        if flags & UInt32(ROADF_ENCHEADERS) != 0 { return true }
        var header = RARHeaderDataEx()
        while RARReadHeaderEx(handle, &header) == ERAR_SUCCESS {
            if header.Flags & UInt32(RHDF_ENCRYPTED) != 0 { return true }
            RARProcessFileW(handle, RAR_SKIP, nil, nil)
        }
        return context.askedForPassword
    }

    // MARK: 工具

    private static func wide(_ string: String) -> [wchar_t] {
        string.unicodeScalars.map { wchar_t(bitPattern: $0.value) } + [0]
    }

    private static func fileName(of header: inout RARHeaderDataEx) -> String {
        withUnsafeBytes(of: &header.FileNameW) { raw in
            let chars = raw.bindMemory(to: wchar_t.self)
            var scalars = String.UnicodeScalarView()
            for c in chars {
                if c == 0 { break }
                if let scalar = Unicode.Scalar(UInt32(bitPattern: c)) { scalars.append(scalar) }
            }
            return String(scalars).replacingOccurrences(of: "\\", with: "/")
        }
    }

    /// RAR 头里的时间是 MS-DOS 格式。
    private static func dosDate(_ value: UInt32) -> Date? {
        var parts = DateComponents()
        parts.year = Int((value >> 25) & 0x7f) + 1980
        parts.month = Int((value >> 21) & 0x0f)
        parts.day = Int((value >> 16) & 0x1f)
        parts.hour = Int((value >> 11) & 0x1f)
        parts.minute = Int((value >> 5) & 0x3f)
        parts.second = Int(value & 0x1f) * 2
        return Calendar.current.date(from: parts)
    }

    private static func error(_ code: Int32, context: Context) -> ArchiveError {
        switch code {
        case ERAR_MISSING_PASSWORD: return .passwordRequired
        case ERAR_BAD_PASSWORD: return .wrongPassword
        case ERAR_BAD_DATA where context.askedForPassword: return .wrongPassword
        case ERAR_EOPEN where context.askedForPassword && context.password == nil: return .passwordRequired
        case ERAR_UNKNOWN_FORMAT, ERAR_BAD_ARCHIVE: return .libarchive("不是有效的 RAR 文件，或文件已损坏。")
        case ERAR_EOPEN: return .libarchive("无法打开压缩包（分卷是否齐全？）。")
        case ERAR_ECREATE, ERAR_EWRITE: return .libarchive("无法写入解压出的文件。")
        default: return .libarchive("RAR 解压失败（错误码 \(code)）。")
        }
    }
}
