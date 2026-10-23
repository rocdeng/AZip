import XCTest
@testable import AZipCore

final class SmokeTests: XCTestCase {
    func testCoreLoads() {
        XCTAssertEqual(AZipCoreVersion.current, "0.1.0")
    }
}
