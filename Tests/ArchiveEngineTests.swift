import XCTest

/// 压缩 / 解压往返测试，直接调用 ArchiveEngine（不依赖界面和沙盒）。
final class ArchiveEngineTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("muz-\(UUID().uuidString)")
        let source = root.appendingPathComponent("资料", isDirectory: true)
        try FileManager.default.createDirectory(at: source.appendingPathComponent("子目录"), withIntermediateDirectories: true)
        try "你好，MacUnZip".write(to: source.appendingPathComponent("说明.txt"), atomically: true, encoding: .utf8)
        try Data(repeating: 7, count: 300_000).write(to: source.appendingPathComponent("子目录/data.bin"))
        try Data().write(to: source.appendingPathComponent(".DS_Store"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var source: URL { root.appendingPathComponent("资料") }

    private func roundTrip(_ format: ArchiveFormat, password: String? = nil) throws -> URL {
        let archive = root.appendingPathComponent("out.\(format.fileExtension)")
        try ArchiveEngine.compress([source], to: archive, format: format, level: .normal, password: password)
        let outDir = root.appendingPathComponent("x-\(format.rawValue)", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let result = try ArchiveEngine.extract(archive, into: outDir, password: password)
        XCTAssertEqual(result.lastPathComponent, "资料", "单个顶层目录应直接放出")
        XCTAssertEqual(try String(contentsOf: result.appendingPathComponent("说明.txt")), "你好，MacUnZip")
        XCTAssertEqual(try Data(contentsOf: result.appendingPathComponent("子目录/data.bin")).count, 300_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.appendingPathComponent(".DS_Store").path))
        return archive
    }

    func testZip() throws { _ = try roundTrip(.zip) }
    func testSevenZip() throws { _ = try roundTrip(.sevenZip) }
    func testTarGz() throws { _ = try roundTrip(.tarGz) }
    func testTarZst() throws { _ = try roundTrip(.tarZst) }

    func testZipWithPassword() throws {
        let archive = try roundTrip(.zip, password: "密码123")
        XCTAssertTrue(ArchiveEngine.needsPassword(archive))
        let outDir = root.appendingPathComponent("nopw", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ArchiveEngine.extract(archive, into: outDir))
        XCTAssertThrowsError(try ArchiveEngine.extract(archive, into: outDir, password: "错的"))
    }

    func testListAndSelectiveExtract() throws {
        let archive = root.appendingPathComponent("sel.zip")
        try ArchiveEngine.compress([source], to: archive, format: .zip, level: .fast)
        let entries = try ArchiveEngine.list(archive)
        XCTAssertEqual(Set(entries.map(\.path)), ["资料", "资料/子目录", "资料/子目录/data.bin", "资料/说明.txt"])

        let outDir = root.appendingPathComponent("sel", isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let result = try ArchiveEngine.extract(archive, into: outDir, only: ["资料/说明.txt"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.appendingPathComponent("说明.txt").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: result.appendingPathComponent("子目录/data.bin").path))
    }

    func testUniqueNameWhenExtractingTwice() throws {
        let archive = root.appendingPathComponent("twice.zip")
        try ArchiveEngine.compress([source], to: archive, format: .zip, level: .fast)
        let first = try ArchiveEngine.extract(archive, into: root)
        let second = try ArchiveEngine.extract(archive, into: root)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(second.lastPathComponent, "资料 2")
    }
}
