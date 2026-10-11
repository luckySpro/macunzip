import Foundation

/// 双击压缩包时的行为，首次启动时由用户选择。
enum DoubleClickBehavior: String, Codable {
    case extractInPlace
    case openWindow
}

/// 压缩后的文件放在哪里。
enum CompressDestination: Codable, Hashable {
    case sameFolder
    case favorite(UUID)
}

/// “保存为默认设置”时记下的压缩选项。密码不在这里，按需存钥匙串。
struct CompressDefaults: Codable, Equatable {
    var format: ArchiveFormat = .zip
    var level: CompressionLevel = .normal
    var destination: CompressDestination = .sameFolder
    var excludeMacMetadata = true
}

/// 主窗口里可点击的常用目录。
struct FavoriteFolder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    /// 主程序创建的安全作用域书签；扩展不使用。
    var bookmark: Data?
}

/// 主程序与访达扩展共用的设置，存在 App Group 里。
final class SharedSettings {
    static let shared = SharedSettings()

    let defaults: UserDefaults
    let appGroupID: String

    private init() {
        appGroupID = Bundle.main.object(forInfoDictionaryKey: "MUZAppGroup") as? String ?? "com.luckyspro.macunzip"
        // 未配置开发者团队时 App Group 前缀为空，组名会和主程序 Bundle ID 相同，
        // 这种 suiteName 无效，改用独立的组名
        if appGroupID == "com.luckyspro.macunzip" { appGroupID = "com.luckyspro.macunzip.shared" }
        defaults = UserDefaults(suiteName: appGroupID) ?? .standard
    }

    var containerURL: URL {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
            ?? FileManager.default.temporaryDirectory
    }

    var onboarded: Bool {
        get { defaults.bool(forKey: "onboarded") }
        set { defaults.set(newValue, forKey: "onboarded") }
    }

    var doubleClickBehavior: DoubleClickBehavior {
        get { decode("doubleClickBehavior") ?? .extractInPlace }
        set { encode(newValue, "doubleClickBehavior") }
    }

    var compressDefaults: CompressDefaults {
        get { decode("compressDefaults") ?? CompressDefaults() }
        set { encode(newValue, "compressDefaults") }
    }

    var favorites: [FavoriteFolder] {
        get { decode("favorites") ?? [] }
        set { encode(newValue, "favorites") }
    }

    /// 默认解压目录；nil 表示“原位置”。
    var defaultExtractFolderID: UUID? {
        get { defaults.string(forKey: "defaultExtractFolderID").flatMap(UUID.init(uuidString:)) }
        set { defaults.set(newValue?.uuidString, forKey: "defaultExtractFolderID") }
    }

    var revealInFinder: Bool {
        get { defaults.object(forKey: "revealInFinder") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "revealInFinder") }
    }

    /// 是否在菜单栏常驻（方案 C）。
    var showMenuBar: Bool {
        get { defaults.bool(forKey: "showMenuBar") }
        set { defaults.set(newValue, forKey: "showMenuBar") }
    }

    var trashArchiveAfterExtract: Bool {
        get { defaults.bool(forKey: "trashArchiveAfterExtract") }
        set { defaults.set(newValue, forKey: "trashArchiveAfterExtract") }
    }

    private func decode<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func encode<T: Encodable>(_ value: T, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }
}
