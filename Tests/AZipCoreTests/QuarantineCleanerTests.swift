import XCTest
@testable import AZipCore

final class QuarantineCleanerTests: XCTestCase {
    private var app: URL!

    override func setUpWithError() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipQuarantineTest-\(UUID().uuidString)")
        app = root.appendingPathComponent("Fake.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data([0xCF, 0xFA, 0xED, 0xFE]).write(to: macOS.appendingPathComponent("Fake"))
        try Data("plist".utf8).write(to: app.appendingPathComponent("Contents/Info.plist"))

        for target in allPaths() {
            setQuarantine(target)
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
    }

    func testDetectsQuarantine() {
        XCTAssertTrue(QuarantineCleaner.hasQuarantine(at: app))
    }

    func testRemovesQuarantineRecursively() {
        let result = QuarantineCleaner.remove(at: app)

        XCTAssertEqual(result.failed.count, 0)
        XCTAssertGreaterThanOrEqual(result.removed, 2)
        for path in allPaths() {
            XCTAssertFalse(QuarantineCleaner.hasQuarantine(at: path), "残留隔离属性：\(path.path)")
        }
    }

    func testIsIdempotent() {
        _ = QuarantineCleaner.remove(at: app)
        let second = QuarantineCleaner.remove(at: app)
        XCTAssertEqual(second.removed, 0)
        XCTAssertEqual(second.failed.count, 0)
    }

    func testDoesNotFollowSymlinks() throws {
        let root = app.deletingLastPathComponent()
        let outside = root.appendingPathComponent("Outside.txt")
        try Data("outside".utf8).write(to: outside)
        let link = app.appendingPathComponent("Contents/OutsideLink")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        setQuarantine(outside)
        setQuarantine(link, options: XATTR_NOFOLLOW)

        let result = QuarantineCleaner.remove(at: app)

        XCTAssertEqual(result.failed.count, 0)
        XCTAssertFalse(
            QuarantineCleaner.hasQuarantine(at: link),
            "符号链接自身的隔离属性应被移除"
        )
        XCTAssertTrue(
            QuarantineCleaner.hasQuarantine(at: outside),
            "不应跟随符号链接修改目标文件"
        )
    }

    private func allPaths() -> [URL] {
        [
            app,
            app.appendingPathComponent("Contents"),
            app.appendingPathComponent("Contents/Info.plist"),
            app.appendingPathComponent("Contents/MacOS"),
            app.appendingPathComponent("Contents/MacOS/Fake")
        ]
    }

    private func setQuarantine(_ url: URL, options: Int32 = 0) {
        let value = "0081;00000000;Safari;"
        value.withCString { pointer in
            url.withUnsafeFileSystemRepresentation { path in
                guard let path else { return }
                _ = setxattr(path, "com.apple.quarantine", pointer, strlen(pointer), 0, options)
            }
        }
    }
}
