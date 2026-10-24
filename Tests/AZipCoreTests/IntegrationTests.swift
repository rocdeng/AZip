import XCTest
@testable import AZipCore

final class IntegrationTests: XCTestCase {
    private var workDirectory: URL!

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        // xcodebuild 只把 TEST_RUNNER_ 前缀的变量透传给测试进程；
        // 直接运行 xctest 时可用 AZIP_INTEGRATION。
        let enabled = environment["AZIP_INTEGRATION"] == "1"
            || environment["TEST_RUNNER_AZIP_INTEGRATION"] == "1"
        try XCTSkipUnless(enabled, "设置 AZIP_INTEGRATION=1（xcodebuild 用 TEST_RUNNER_AZIP_INTEGRATION=1）才运行集成测试")
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipIntegration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    func testMountScanInstallDetach() async throws {
        let dmg = workDirectory.appendingPathComponent("TestApp.dmg")
        try await makeDMG(at: dmg)

        let mount = try await DiskImageMounter.attach(dmg)
        XCTAssertTrue(FileManager.default.fileExists(atPath: mount.mountPoint.path))

        addTeardownBlock {
            try? await DiskImageMounter.detach(mount)
        }

        let entries = try VolumeScanner.scan(directory: mount.mountPoint)
        let apps = VolumeScanner.applications(in: entries)
        XCTAssertEqual(apps.map(\.name), ["TestApp.app"])
        XCTAssertTrue(
            QuarantineCleaner.hasQuarantine(at: apps[0].url),
            "测试镜像里的应用应当带有隔离属性"
        )

        let targetDirectory = workDirectory.appendingPathComponent("Applications")
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)

        let installed = try await AppInstaller.install(
            InstallRequest(
                sourceApp: apps[0].url,
                targetDirectory: targetDirectory,
                overwrite: false,
                registerHandler: { _ in }
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertFalse(QuarantineCleaner.hasQuarantine(at: installed))

        try await DiskImageMounter.detach(mount)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mount.mountPoint.path))
    }

    func testDetachFailsForMissingVolume() async throws {
        let result = MountResult(
            mountPoint: URL(fileURLWithPath: "/Volumes/AZipDoesNotExist-\(UUID().uuidString)"),
            deviceEntry: "/dev/disk999",
            volumeName: "DoesNotExist"
        )
        do {
            try await DiskImageMounter.detach(result)
            XCTFail("对一个不存在的设备卸载应当失败")
        } catch {
            // 预期：hdiutil 返回非 0 并抛出 toolFailed
        }
    }

    private func makeDMG(at url: URL) async throws {
        let stage = workDirectory.appendingPathComponent("stage")
        let macOS = stage.appendingPathComponent("TestApp.app/Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try Data("hi".utf8).write(to: macOS.appendingPathComponent("TestApp"))
        try Data("<plist/>".utf8).write(to: stage.appendingPathComponent("TestApp.app/Contents/Info.plist"))
        try FileManager.default.createSymbolicLink(
            at: stage.appendingPathComponent("Applications"),
            withDestinationURL: URL(fileURLWithPath: "/Applications")
        )

        // 模拟从网络下载的应用，验证安装流程确实会清除隔离属性。
        let quarantined = stage.appendingPathComponent("TestApp.app")
        let setxattr = try await ProcessRunner.run(
            "/usr/bin/xattr",
            ["-w", QuarantineCleaner.attributeName, "0081;00000000;AZipTest;", quarantined.path],
            timeoutSeconds: 30
        )
        XCTAssertEqual(setxattr.status, 0, setxattr.stderr)

        let result = try await ProcessRunner.run(
            "/usr/bin/hdiutil",
            ["create", "-volname", "AZipTest", "-srcfolder", stage.path, "-ov", "-format", "UDZO", url.path],
            timeoutSeconds: 120
        )
        XCTAssertEqual(result.status, 0, result.stderr)
    }
}
