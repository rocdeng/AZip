import XCTest
@testable import AZipCore

final class LanguageTests: XCTestCase {
    private var previousRaw: String?
    private var previousAppleLanguages: Any?

    override func setUp() {
        super.setUp()
        previousRaw = UserDefaults.standard.string(forKey: "appLanguage")
        previousAppleLanguages = UserDefaults.standard.object(forKey: "AppleLanguages")
    }

    override func tearDown() {
        if let previousRaw {
            UserDefaults.standard.set(previousRaw, forKey: "appLanguage")
        } else {
            UserDefaults.standard.removeObject(forKey: "appLanguage")
        }
        if let previousAppleLanguages {
            UserDefaults.standard.set(previousAppleLanguages, forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
        super.tearDown()
    }

    func testDefaultIsSystem() {
        UserDefaults.standard.removeObject(forKey: "appLanguage")
        XCTAssertEqual(AppLanguage.current, .system)
    }

    func testSwitchingToEnglishTranslatesStringsAndFileTypes() {
        AppLanguage.current = .en
        XCTAssertEqual(AZipCore.NSLocalizedString("文件关联", comment: ""), "File Associations")
        XCTAssertEqual(AZipCore.NSLocalizedString("安装应用", comment: ""), "Install App")
        XCTAssertEqual(FileAssociationService.supportedTypes.first?.label, "DMG Disk Image")
    }

    func testSwitchingToSimplifiedChineseUsesDeAIfiedStrings() {
        AppLanguage.current = .zhHans
        XCTAssertEqual(
            AZipCore.NSLocalizedString("勾选后，双击对应文件将由 AZip 打开。", comment: ""),
            "开启后，在访达里双击对应格式会直接用 AZip 打开。"
        )
        XCTAssertEqual(FileAssociationService.supportedTypes.first?.label, "DMG 磁盘映像")
    }
}
