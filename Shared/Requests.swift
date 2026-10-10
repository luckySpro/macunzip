import Foundation

/// 访达扩展交给主程序的一次操作。扩展把它写进 App Group，
/// 再用 macunzip://request/<id> 唤起主程序读取。
struct FinderRequest: Codable {
    enum Action: String, Codable {
        case quickCompress   // 按默认设置直接压缩
        case compress        // 弹出压缩面板
        case extractHere
        case extractTo
        case preview         // 打开内容预览
    }

    var id = UUID()
    var action: Action
    var paths: [String]

    var urls: [URL] { paths.map { URL(fileURLWithPath: $0) } }

    private static var directory: URL {
        SharedSettings.shared.containerURL.appendingPathComponent("Requests", isDirectory: true)
    }

    /// 写入请求并返回唤起主程序用的 URL。
    func write() throws -> URL {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.directory.appendingPathComponent("\(id.uuidString).json"))
        return URL(string: "macunzip://request/\(id.uuidString)")!
    }

    /// 读取并删除请求文件。
    static func take(id: String) -> FinderRequest? {
        let file = directory.appendingPathComponent("\(id).json")
        defer { try? FileManager.default.removeItem(at: file) }
        return (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(FinderRequest.self, from: $0) }
    }
}
