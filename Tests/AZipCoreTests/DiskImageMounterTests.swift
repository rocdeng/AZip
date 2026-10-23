import XCTest
@testable import AZipCore

final class DiskImageMounterTests: XCTestCase {
    func testParsesMountPointFromFixture() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "attach_plist", withExtension: "txt"))
        let data = try Data(contentsOf: url)
        let result = try DiskImageMounter.parseAttachOutput(data)
        XCTAssertEqual(result.mountPoint.path, "/Volumes/TestApp")
        XCTAssertEqual(result.deviceEntry, "/dev/disk9s1")
        XCTAssertEqual(result.volumeName, "TestApp")
    }

    func testParsesPlistWithoutMountPoint() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict><key>system-entities</key><array>
        <dict><key>dev-entry</key><string>/dev/disk9</string></dict>
        </array></dict>
        </plist>
        """
        XCTAssertThrowsError(try DiskImageMounter.parseAttachOutput(Data(xml.utf8))) { error in
            guard case MountError.noMountPointFound = error else {
                return XCTFail("错误类型不符：\(error)")
            }
        }
    }
}
