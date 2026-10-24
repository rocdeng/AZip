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
            InstallRequest(
                sourceApp: source,
                targetDirectory: targetDirectory,
                overwrite: false,
                registerHandler: { _ in }
            )
        )

        XCTAssertEqual(installed.lastPathComponent, "Fake.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try marker(of: installed), "v1")
    }

    func testThrowsConflictWhenTargetExistsWithoutOverwrite() async throws {
        _ = try await AppInstaller.install(
            InstallRequest(
                sourceApp: source,
                targetDirectory: targetDirectory,
                overwrite: false,
                registerHandler: { _ in }
            )
        )

        do {
            _ = try await AppInstaller.install(
                InstallRequest(
                    sourceApp: source,
                    targetDirectory: targetDirectory,
                    overwrite: false,
                    registerHandler: { _ in }
                )
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
            InstallRequest(
                sourceApp: source,
                targetDirectory: targetDirectory,
                overwrite: false,
                registerHandler: { _ in }
            )
        )

        try makeFakeApp(at: source, marker: "v2")

        let trashed = TrashSpy()
        let installed = try await AppInstaller.install(
            InstallRequest(
                sourceApp: source,
                targetDirectory: targetDirectory,
                overwrite: true,
                trashHandler: { url in trashed.record(url) },
                registerHandler: { _ in }
            )
        )

        XCTAssertEqual(try marker(of: installed), "v2")
        XCTAssertEqual(trashed.urls.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashed.urls[0].path))
    }

    // MARK: - commitStaged

    func testCommitStagedMovesStagedAppWhenTargetAbsent() throws {
        let staged = root.appendingPathComponent("Staging/Fake.app")
        try makeFakeApp(at: staged, marker: "staged")
        let finalURL = targetDirectory.appendingPathComponent("Fake.app")
        let trash = TrashSpy()

        let installed = try AppInstaller.commitStaged(
            stagingApp: staged,
            finalURL: finalURL,
            targetDirectory: targetDirectory,
            overwrite: false,
            trashHandler: { trash.record($0) }
        )

        XCTAssertEqual(installed.lastPathComponent, "Fake.app")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: staged.path))
        XCTAssertEqual(try marker(of: installed), "staged")
        XCTAssertTrue(trash.urls.isEmpty)
    }

    func testCommitStagedWithoutOverwriteLeavesConcurrentTargetUntouched() throws {
        let staged = root.appendingPathComponent("Staging/Fake.app")
        try makeFakeApp(at: staged, marker: "new")
        // 模拟 ditto 期间被其他进程创建的目标应用。
        let finalURL = targetDirectory.appendingPathComponent("Fake.app")
        try makeFakeApp(at: finalURL, marker: "concurrent")
        let trash = TrashSpy()

        XCTAssertThrowsError(
            try AppInstaller.commitStaged(
                stagingApp: staged,
                finalURL: finalURL,
                targetDirectory: targetDirectory,
                overwrite: false,
                trashHandler: { trash.record($0) }
            )
        ) { error in
            guard let installError = error as? InstallError,
                  case .conflict(let conflictURL) = installError else {
                return XCTFail("错误类型不符：\(error)")
            }
            XCTAssertEqual(conflictURL.path, finalURL.path)
        }

        XCTAssertEqual(try marker(of: finalURL), "concurrent")
        XCTAssertTrue(trash.urls.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: staged.path))
    }

    func testCommitStagedWithOverwriteTrashesOldAppAndInstallsNew() throws {
        let staged = root.appendingPathComponent("Staging/Fake.app")
        try makeFakeApp(at: staged, marker: "new")
        let finalURL = targetDirectory.appendingPathComponent("Fake.app")
        try makeFakeApp(at: finalURL, marker: "old")
        let trash = TrashSpy()

        let installed = try AppInstaller.commitStaged(
            stagingApp: staged,
            finalURL: finalURL,
            targetDirectory: targetDirectory,
            overwrite: true,
            trashHandler: { trash.record($0) }
        )

        XCTAssertEqual(try marker(of: installed), "new")
        XCTAssertEqual(trash.urls.count, 1)
        XCTAssertTrue(trash.urls[0].lastPathComponent.hasPrefix(AppInstaller.backupPrefix))
        XCTAssertEqual(
            trash.urls[0].deletingLastPathComponent().resolvingSymlinksInPath().path,
            targetDirectory.resolvingSymlinksInPath().path
        )
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
                InstallRequest(
                    sourceApp: source,
                    targetDirectory: readOnly,
                    overwrite: false,
                    registerHandler: { _ in }
                )
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
                InstallRequest(
                    sourceApp: folder,
                    targetDirectory: targetDirectory,
                    overwrite: false,
                    registerHandler: { _ in }
                )
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
            InstallRequest(
                sourceApp: source,
                targetDirectory: targetDirectory,
                overwrite: false,
                registerHandler: { _ in }
            )
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

    private func marker(of app: URL) throws -> String {
        try String(contentsOf: app.appendingPathComponent("Contents/MacOS/marker"), encoding: .utf8)
    }

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
