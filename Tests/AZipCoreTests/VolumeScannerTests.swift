import XCTest
@testable import AZipCore

final class VolumeScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipScanTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try makeApp(named: "MultiChat.app")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Docs"), withIntermediateDirectories: true
        )
        try Data("hello".utf8).write(to: root.appendingPathComponent("readme.txt"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".background"), withIntermediateDirectories: true
        )
        try Data([]).write(to: root.appendingPathComponent(".DS_Store"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Applications"),
            withDestinationURL: URL(fileURLWithPath: "/Applications")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFiltersHiddenAndSystemEntries() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let names = entries.map(\.name)

        XCTAssertFalse(names.contains(".DS_Store"))
        XCTAssertFalse(names.contains(".background"))
        XCTAssertTrue(names.contains("Applications"), "DMG 里的 Applications 快捷方式要保留，用于按背景图定位显示")
        XCTAssertTrue(names.contains("MultiChat.app"))
        XCTAssertTrue(names.contains("Docs"))
        XCTAssertTrue(names.contains("readme.txt"))
    }

    func testClassifiesKinds() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0.kind) })

        XCTAssertEqual(byName["MultiChat.app"], .application)
        XCTAssertEqual(byName["Docs"], .folder)
        XCTAssertEqual(byName["readme.txt"], .file)
        XCTAssertEqual(byName["Applications"], .symbolicLink)
    }

    func testSortsFoldersAndAppsBeforeFiles() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let firstThree = Set(entries.prefix(3).map(\.name))
        XCTAssertTrue(firstThree.contains("MultiChat.app"))
        XCTAssertTrue(firstThree.contains("Docs"))
    }

    func testApplicationsHelper() throws {
        let entries = try VolumeScanner.scan(directory: root)
        XCTAssertEqual(VolumeScanner.applications(in: entries).map(\.name), ["MultiChat.app"])
    }

    func testReportsFileSize() throws {
        let entries = try VolumeScanner.scan(directory: root)
        let readme = try XCTUnwrap(entries.first { $0.name == "readme.txt" })
        XCTAssertEqual(readme.byteSize, 5)
        XCTAssertNil(entries.first { $0.name == "Docs" }?.byteSize)
    }

    private func makeApp(named name: String) throws {
        let bundle = root.appendingPathComponent(name)
        let macOS = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data().write(to: macOS.appendingPathComponent("Binary"))
    }
}
