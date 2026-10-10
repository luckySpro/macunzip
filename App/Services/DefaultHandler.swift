import AppKit
import UniformTypeIdentifiers

/// 把 MacUnZip 设为常见压缩格式的默认打开方式。
enum DefaultHandler {
    static let typeIdentifiers = [
        "public.zip-archive", "com.rarlab.rar-archive", "org.7-zip.7-zip-archive",
        "public.tar-archive", "org.gnu.gnu-zip-archive", "org.gnu.gnu-zip-tar-archive",
        "org.tukaani.xz-archive", "public.bzip2-archive", "com.facebook.zstandard-archive",
    ]

    /// 返回设置失败的类型（系统可能弹出确认，用户拒绝也算失败）。
    static func makeDefault() async -> [String] {
        var failed: [String] = []
        for id in typeIdentifiers {
            guard let type = UTType(id) else { continue }
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type)
            } catch {
                failed.append(type.preferredFilenameExtension ?? id)
            }
        }
        return failed
    }

    static var isDefaultForZip: Bool {
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: .zip) else { return false }
        return app.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}
