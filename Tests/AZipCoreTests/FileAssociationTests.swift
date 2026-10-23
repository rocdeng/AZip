import XCTest
@testable import AZipCore

final class FileAssociationTests: XCTestCase {
    func testDeclaresBothDiskImageUTIs() {
        XCTAssertEqual(
            FileAssociationService.diskImageUTIs,
            ["com.apple.disk-image-udif", "public.disk-image"]
        )
    }

    func testPrimaryUTIIsConcreteDiskImageType() {
        XCTAssertEqual(
            FileAssociationService.diskImageUTIs.first,
            "com.apple.disk-image-udif",
            "isDefault 与 restoreSystemDefault 都以第一个 UTI 为权威，它必须是具体类型"
        )
    }

    func testCanQueryCurrentHandlerWithoutMutating() {
        // 具体 UTI 在 macOS 上始终有处理程序；父类型在未注册本应用时可能为 nil。
        let handler = FileAssociationService.currentHandler(for: "com.apple.disk-image-udif")
        XCTAssertNotNil(handler, "系统应当至少有默认的磁盘映像处理程序")
    }

    func testIsDefaultIsFalseForUnknownBundle() {
        XCTAssertFalse(FileAssociationService.isDefault(bundleID: "com.dengpeng.AZip.not-installed"))
    }
}
