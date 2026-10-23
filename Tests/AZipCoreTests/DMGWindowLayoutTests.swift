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
    }

    func testPrefersNamedBackgroundFromAlias() throws {
        let named = mountPoint.appendingPathComponent(".background/brand.png")
        let other = mountPoint.appendingPathComponent(".background/other.png")
        try Data([1]).write(to: named)
        try Data([2]).write(to: other)

        // 直接验证「优先按 alias 解析出的文件名匹配」这条规则。
        let url = DMGWindowLayout.backgroundImage(
            mountPoint: mountPoint, fileName: "brand.png"
        )
        XCTAssertEqual(url?.lastPathComponent, "brand.png")
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
    }

    func testMakeDefaultsWindowSizeWhenMissing() {
        var document = DSStoreDocument()
        document.iconPositions = ["A.app": CGPoint(x: 10, y: 10)]

        let layout = DMGWindowLayout.make(mountPoint: mountPoint, document: document)
        XCTAssertEqual(layout?.contentSize.width, 640)
        XCTAssertEqual(layout?.contentSize.height, 400)
    }
}
