import XCTest
@testable import AZipCore

final class AppInstallerTests: XCTestCase {
    private var root: URL!
    private var source: URL!
    private var targetDirectory: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipInstallerTest-\(UUID().uuidString)")
        source = root.appendingPathComponent("Source/Fake.app")
        targetDirectory = root.appendingPathComponent("Applications")
        try makeFakeApp(at: source, marker: "v1")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInstallsApp() async throws {
        let installed = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        XCTAssertEqual(installed.lastPathComponent, "Fake.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        let marker = try String(contentsOf: installed.appendingPathComponent("Contents/MacOS/marker"), encoding: .utf8)
        XCTAssertEqual(marker, "v1")
    }

    func testThrowsConflictWhenTargetExistsWithoutOverwrite() async throws {
        _ = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        do {
            _ = try await AppInstaller.install(
                InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
            )
            XCTFail("应当抛出冲突")
        } catch let error as InstallError {
            guard case .conflict = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testOverwriteReplacesAppAndTrashesOldVersion() async throws {
        _ = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        try makeFakeApp(at: source, marker: "v2")

        let trashed = TrashSpy()
        let installed = try await AppInstaller.install(
            InstallRequest(
                sourceApp: source,
                targetDirectory: targetDirectory,
                overwrite: true,
                trashHandler: { url in trashed.record(url) }
            )
        )

        let marker = try String(contentsOf: installed.appendingPathComponent("Contents/MacOS/marker"), encoding: .utf8)
        XCTAssertEqual(marker, "v2")
        XCTAssertEqual(trashed.urls.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.urls[0].path))
    }

    func testRejectsNonWritableTarget() async throws {
        let readOnly = root.appendingPathComponent("ReadOnly")
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: readOnly.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: readOnly.path)
        }

        do {
            _ = try await AppInstaller.install(
                InstallRequest(sourceApp: source, targetDirectory: readOnly, overwrite: false)
            )
            XCTFail("应当抛出权限错误")
        } catch let error as InstallError {
            guard case .targetNotWritable = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testRejectsNonApplicationSource() async throws {
        let folder = root.appendingPathComponent("NotAnApp")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        do {
            _ = try await AppInstaller.install(
                InstallRequest(sourceApp: folder, targetDirectory: targetDirectory, overwrite: false)
            )
            XCTFail("应当抛出无效源错误")
        } catch let error as InstallError {
            guard case .invalidSource = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }

    func testLeavesNoStagingResidue() async throws {
        _ = try await AppInstaller.install(
            InstallRequest(sourceApp: source, targetDirectory: targetDirectory, overwrite: false)
        )

        let leftovers = try FileManager.default
            .contentsOfDirectory(atPath: targetDirectory.path)
            .filter { $0.hasPrefix(AppInstaller.stagingPrefix) }
        XCTAssertTrue(leftovers.isEmpty, "残留 staging：\(leftovers)")
    }

    func testFindsPendingBackups() async throws {
        let backup = targetDirectory.appendingPathComponent("\(AppInstaller.backupPrefix)abc.app")
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)

        // URL 相等性会受 /var 与 /private/var 以及目录尾斜杠影响，
        // 这里比较解析符号链接后的路径，断言意图不变：恰好找到该备份。
        XCTAssertEqual(
            AppInstaller.pendingBackups(in: targetDirectory)
                .map { $0.resolvingSymlinksInPath().path },
            [backup.resolvingSymlinksInPath().path]
        )
    }

    // MARK: - Helpers

    private func makeFakeApp(at url: URL, marker: String) throws {
        try? FileManager.default.removeItem(at: url)
        let macOS = url.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data(marker.utf8).write(to: macOS.appendingPathComponent("marker"))
        try Data("<plist/>".utf8).write(to: url.appendingPathComponent("Contents/Info.plist"))
    }
}

private final class TrashSpy: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var urls: [URL] = []

    @discardableResult
    func record(_ url: URL) -> Bool {
        lock.lock()
        urls.append(url)
        lock.unlock()
        try? FileManager.default.removeItem(at: url)
        return true
    }
}
