import XCTest
@testable import AZipCore

final class FileAssociationTests: XCTestCase {
    func testDeclaresBothDiskImageUTIs() {
        XCTAssertEqual(
            FileAssociationService.diskImageUTIs,
            ["com.apple.disk-image-udif", "public.disk-image"]
        )
    }

    func testCanQueryCurrentHandlerWithoutMutating() {
        let handler = FileAssociationService.currentHandler(for: "public.disk-image")
        XCTAssertNotNil(handler, "系统应当至少有默认的磁盘映像处理程序")
    }

    func testIsDefaultIsFalseForUnknownBundle() {
        XCTAssertFalse(FileAssociationService.isDefault(bundleID: "com.dengpeng.AZip.not-installed"))
    }
}
