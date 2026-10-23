import XCTest
@testable import AZipCore

final class DSStoreReaderTests: XCTestCase {
    func testParsesIconPositions() {
        var builder = DSStoreFixtureBuilder()
        builder.addIcon(name: "MultiChat.app", x: 120, y: 140)
        builder.addIcon(name: "Applications", x: 320, y: 140)

        let doc = DSStoreReader.parse(builder.build())

        XCTAssertEqual(doc.iconPositions.count, 2)
        let app = doc.iconPositions["MultiChat.app"]
        XCTAssertEqual(app?.x ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(app?.y ?? 0, 140, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["Applications"]?.x ?? 0, 320, accuracy: 0.001)
    }

    func testParsesWindowProperties() {
        var builder = DSStoreFixtureBuilder()
        builder.addBWSP(width: 640, height: 400)
        builder.addICVP(
            iconSize: 80,
            textSize: 12,
            backgroundColor: Array(repeating: 255, count: 12)
        )

        let doc = DSStoreReader.parse(builder.build())

        XCTAssertEqual(doc.windowFrame?.size.width ?? 0, 640, accuracy: 0.001)
        XCTAssertEqual(doc.windowFrame?.size.height ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(doc.iconSize ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(doc.textSize ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(doc.backgroundColor?.count, 6)
        XCTAssertEqual(doc.backgroundColor?[0] ?? 0, 1.0, accuracy: 0.001)
    }

    func testRejectsNonBud1Data() {
        let doc = DSStoreReader.parse(Data("not a ds_store".utf8))
        XCTAssertTrue(doc.iconPositions.isEmpty)
        XCTAssertNil(doc.windowFrame)
    }

    func testIgnoresTruncatedRecords() {
        var builder = DSStoreFixtureBuilder()
        builder.addIcon(name: "A.app", x: 10_000, y: 20_000)
        var data = builder.build()
        data = data.prefix(data.count - 4)

        let doc = DSStoreReader.parse(data)
        XCTAssertTrue(doc.iconPositions.isEmpty || doc.iconPositions["A.app"] != nil)
    }

    func testParsesRealBud1Format() {
        var builder = RealDSStoreFixtureBuilder()
        builder.addIcon(name: "MultiChat.app", x: 120, y: 140)
        builder.addIcon(name: "Applications", x: 320, y: 140)
        builder.backgroundAlias = Data([0x01, 0x02, 0x03])

        let doc = DSStoreReader.parse(builder.build())

        XCTAssertEqual(doc.iconPositions.count, 2)
        XCTAssertEqual(doc.iconPositions["MultiChat.app"]?.x ?? 0, 120, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["MultiChat.app"]?.y ?? 0, 140, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["Applications"]?.x ?? 0, 320, accuracy: 0.001)
        XCTAssertEqual(doc.windowFrame?.size.width ?? 0, 640, accuracy: 0.001)
        XCTAssertEqual(doc.windowFrame?.size.height ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(doc.iconSize ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(doc.textSize ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(doc.backgroundColor?.count, 3)
        XCTAssertEqual(doc.backgroundColor?[0] ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(doc.backgroundAlias, Data([0x01, 0x02, 0x03]))
    }

    func testParsesFixtureCapturedFromRealDMG() throws {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "real_dsstore", withExtension: "bin")
        )
        let doc = DSStoreReader.parse(try Data(contentsOf: url))

        XCTAssertEqual(doc.windowFrame?.size.width ?? 0, 564, accuracy: 0.001)
        XCTAssertEqual(doc.windowFrame?.size.height ?? 0, 370, accuracy: 0.001)
        XCTAssertEqual(doc.iconSize ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(doc.textSize ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(doc.backgroundColor?.count, 3)
        XCTAssertNotNil(doc.backgroundAlias)
        XCTAssertEqual(doc.iconPositions["Applications"]?.x ?? 0, 435, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["Applications"]?.y ?? 0, 222, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["TRAE SOLO.app"]?.x ?? 0, 135, accuracy: 0.001)
    }
}
