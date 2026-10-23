import XCTest
@testable import AZipCore

final class DMGWindowLayoutTests: XCTestCase {
    private var mountPoint: URL!

    override func setUpWithError() throws {
        mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipLayoutTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: mountPoint.appendingPathComponent(".background"),
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: mountPoint)
    }

    func testResolvesBackgroundFromDotBackgroundDirectory() throws {
        let image = mountPoint.appendingPathComponent(".background/bg.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: image)

        let url = DMGWindowLayout.resolveBackgroundImage(
            mountPoint: mountPoint, document: DSStoreDocument()
        )

        XCTAssertEqual(url?.lastPathComponent, "bg.png")
        // 普通常规文件不能被过度拒绝。
        XCTAssertEqual(
            DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: "bg.png")?
                .lastPathComponent,
            "bg.png"
        )
    }

    func testRejectsSymlinkedBackgroundDirectory() throws {
        let external = try makeExternalDirectory()
        try Data([1]).write(to: external.appendingPathComponent("bg.png"))

        let backgroundDirectory = mountPoint.appendingPathComponent(".background")
        try FileManager.default.removeItem(at: backgroundDirectory)
        try FileManager.default.createSymbolicLink(
            at: backgroundDirectory,
            withDestinationURL: external
        )

        XCTAssertNil(
            DMGWindowLayout.resolveBackgroundImage(
                mountPoint: mountPoint, document: DSStoreDocument()
            )
        )
        XCTAssertNil(
            DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: "bg.png")
        )
    }

    func testRejectsSymlinkedBackgroundImage() throws {
        let external = try makeExternalDirectory()
        let target = external.appendingPathComponent("real.png")
        try Data([1]).write(to: target)

        try FileManager.default.createSymbolicLink(
            at: mountPoint.appendingPathComponent(".background/bg.png"),
            withDestinationURL: target
        )

        XCTAssertNil(
            DMGWindowLayout.resolveBackgroundImage(
                mountPoint: mountPoint, document: DSStoreDocument()
            )
        )
        XCTAssertNil(
            DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: "bg.png")
        )
    }

    func testPrefersNamedBackgroundOverAlphabeticalEntry() throws {
        try Data([2]).write(to: mountPoint.appendingPathComponent(".background/aaa.png"))
        try Data([1]).write(to: mountPoint.appendingPathComponent(".background/brand.png"))

        // 无 alias 时回退扫描按字母序取第一个，说明下面的命名查找确实不是「取第一个」。
        XCTAssertEqual(
            DMGWindowLayout.resolveBackgroundImage(
                mountPoint: mountPoint, document: DSStoreDocument()
            )?.lastPathComponent,
            "aaa.png"
        )
        XCTAssertEqual(
            DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: "brand.png")?
                .lastPathComponent,
            "brand.png"
        )
        // 请求的名字不存在时返回 nil，而不是回退到其它图片。
        XCTAssertNil(
            DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: "missing.png")
        )
    }

    func testRejectsAliasDerivedNameWithoutImageExtension() throws {
        try Data([1]).write(to: mountPoint.appendingPathComponent(".background/Applications"))

        XCTAssertNil(
            DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: "Applications")
        )
        XCTAssertNil(
            DMGWindowLayout.resolveBackgroundImage(
                mountPoint: mountPoint, document: DSStoreDocument()
            )
        )
    }

    func testResolveAliasFileNameRejectsEmptyAndGarbage() {
        XCTAssertNil(DMGWindowLayout.resolveAliasFileName(Data()))
        XCTAssertNil(DMGWindowLayout.resolveAliasFileName(Data([0x00, 0x01, 0x02, 0x03])))
        XCTAssertNil(
            DMGWindowLayout.resolveAliasFileName(Data(repeating: 0xFF, count: 256))
        )
    }

    func testReturnsNilWhenNoBackgroundExists() {
        XCTAssertNil(
            DMGWindowLayout.resolveBackgroundImage(
                mountPoint: mountPoint, document: DSStoreDocument()
            )
        )
    }

    func testRejectsPathTraversalInAliasFileName() {
        let url = DMGWindowLayout.backgroundImage(
            mountPoint: mountPoint, fileName: "../../etc/passwd"
        )
        XCTAssertNil(url)
        XCTAssertNil(DMGWindowLayout.backgroundImage(mountPoint: mountPoint, fileName: ".."))
    }

    func testMakeReturnsNilWhenNothingToLayout() {
        let document = DSStoreDocument()
        XCTAssertNil(DMGWindowLayout.make(mountPoint: mountPoint, document: document))
    }

    func testMakeUsesWindowSizeAndIconSize() {
        var document = DSStoreDocument()
        document.windowFrame = CGRect(x: 0, y: 0, width: 640, height: 400)
        document.iconSize = 80
        document.iconPositions = ["A.app": CGPoint(x: 120, y: 140)]

        let layout = DMGWindowLayout.make(mountPoint: mountPoint, document: document)

        XCTAssertEqual(layout?.contentSize.width, 640)
        XCTAssertEqual(layout?.contentSize.height, 400)
        XCTAssertEqual(layout?.iconSize, 80)
        XCTAssertEqual(layout?.iconPositions["A.app"]?.x, 120)
    }

    func testMakeClampsIconSizeToReasonableRange() {
        var document = DSStoreDocument()
        document.iconSize = 1000
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        XCTAssertEqual(DMGWindowLayout.make(mountPoint: mountPoint, document: document)?.iconSize, 128)

        document.iconSize = 1
        XCTAssertEqual(DMGWindowLayout.make(mountPoint: mountPoint, document: document)?.iconSize, 48)
    }

    func testMakeFallsBackWhenIconSizeIsNotFinite() {
        var document = DSStoreDocument()
        document.iconSize = .nan
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        let layout = DMGWindowLayout.make(mountPoint: mountPoint, document: document)

        XCTAssertEqual(layout?.iconSize, DMGWindowLayout.defaultIconSize)
        XCTAssertEqual(layout?.iconSize.isFinite, true)
    }

    func testMakeFallsBackWhenWindowSizeIsNotFinite() {
        var document = DSStoreDocument()
        document.windowFrame = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 400)
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        let layout = DMGWindowLayout.make(mountPoint: mountPoint, document: document)

        XCTAssertEqual(layout?.contentSize, DMGWindowLayout.defaultSize)
        XCTAssertEqual(layout?.contentSize.width.isFinite, true)
        XCTAssertEqual(layout?.contentSize.height.isFinite, true)
    }

    func testMakeClampsWindowSizeAtBothBounds() {
        var document = DSStoreDocument()
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        document.windowFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        XCTAssertEqual(
            DMGWindowLayout.make(mountPoint: mountPoint, document: document)?.contentSize,
            DMGWindowLayout.minimumSize
        )

        document.windowFrame = CGRect(x: 0, y: 0, width: 5000, height: 5000)
        XCTAssertEqual(
            DMGWindowLayout.make(mountPoint: mountPoint, document: document)?.contentSize,
            DMGWindowLayout.maximumSize
        )
    }

    func testMakeDefaultsWindowSizeWhenMissing() {
        var document = DSStoreDocument()
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        let layout = DMGWindowLayout.make(mountPoint: mountPoint, document: document)
        XCTAssertEqual(layout?.contentSize.width, 640)
        XCTAssertEqual(layout?.contentSize.height, 400)
    }

    // MARK: - Helpers

    /// 创建仅由本测试使用、仅由本测试删除的外部临时目录。
    private func makeExternalDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AZipLayoutExternal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}
