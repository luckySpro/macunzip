import Foundation

/// 压缩时可选的输出格式。解压支持 libarchive 能识别的全部格式。
enum ArchiveFormat: String, Codable, CaseIterable, Identifiable {
    case zip
    case sevenZip = "7z"
    case tarGz = "tar.gz"
    case tarZst = "tar.zst"

    var id: String { rawValue }
    var fileExtension: String { rawValue }
    var displayName: String {
        switch self {
        case .zip: return "ZIP"
        case .sevenZip: return "7z"
        case .tarGz: return "tar.gz"
        case .tarZst: return "tar.zst"
        }
    }
    /// libarchive 目前只对 ZIP 支持写入加密。
    var supportsPassword: Bool { self == .zip }

    /// 可以双击打开 / 解压的扩展名。
    static let readableExtensions: Set<String> = [
        "zip", "rar", "7z", "tar", "gz", "tgz", "xz", "txz", "bz2", "tbz", "tbz2",
        "zst", "tzst", "lz4", "iso", "cpio", "xar", "lha", "lzh", "cab",
    ]

    static func isArchive(_ url: URL) -> Bool {
        readableExtensions.contains(url.pathExtension.lowercased())
    }
}

/// 压缩率档位，界面上是“仅存储 / 快速 / 标准 / 最高”。
enum CompressionLevel: Int, Codable, CaseIterable, Identifiable {
    case store = 0, fast = 1, normal = 6, best = 9
    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .store: return "仅存储"
        case .fast: return "快速"
        case .normal: return "标准"
        case .best: return "最高"
        }
    }
}
