import XCTest
@testable import AZipCore

final class DSStoreReaderTests: XCTestCase {
    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "bin")
        )
        return try Data(contentsOf: url)
    }

    func testParsesIconPositions() {
        var builder = RealDSStoreFixtureBuilder()
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
        // 构造器默认写入 640x400 窗口、iconSize 80、textSize 12、白色背景。
        let builder = RealDSStoreFixtureBuilder()

        let doc = DSStoreReader.parse(builder.build())

        XCTAssertEqual(doc.windowFrame?.size.width ?? 0, 640, accuracy: 0.001)
        XCTAssertEqual(doc.windowFrame?.size.height ?? 0, 400, accuracy: 0.001)
        XCTAssertEqual(doc.iconSize ?? 0, 80, accuracy: 0.001)
        XCTAssertEqual(doc.textSize ?? 0, 12, accuracy: 0.001)
        XCTAssertEqual(doc.backgroundColor?.count, 3)
        XCTAssertEqual(doc.backgroundColor?[0] ?? 0, 1.0, accuracy: 0.001)
    }

    func testRejectsNonBud1Data() {
        let doc = DSStoreReader.parse(Data("not a ds_store".utf8))
        XCTAssertTrue(doc.iconPositions.isEmpty)
        XCTAssertNil(doc.windowFrame)
    }

    func testIgnoresTruncatedRecords() {
        var builder = RealDSStoreFixtureBuilder()
        builder.addIcon(name: "A.app", x: 10_000, y: 20_000)
        let data = builder.build()

        let doc = DSStoreReader.parse(data.prefix(data.count - 4))

        // 截断使叶子块的 buddy 区间越界（end > data.count），遍历整体放弃；
        // 解析器保证返回空文档而不是越界读取。
        XCTAssertTrue(doc.iconPositions.isEmpty)
        XCTAssertNil(doc.windowFrame)
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
        let doc = DSStoreReader.parse(try fixtureData("real_dsstore"))

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

    // MARK: - 切片与 B-tree 结构

    func testParsesNonZeroBasedSliceIdentically() throws {
        let whole = try fixtureData("real_dsstore")
        let padded = Data([0xEE, 0xEE]) + whole + Data([0xEE])
        let slice = padded[2..<(2 + whole.count)]
        XCTAssertEqual(slice.startIndex, 2)

        let expected = DSStoreReader.parse(whole)
        let actual = DSStoreReader.parse(slice)

        XCTAssertEqual(actual.iconPositions, expected.iconPositions)
        XCTAssertEqual(actual.windowFrame, expected.windowFrame)
        XCTAssertEqual(actual.iconSize, expected.iconSize)
        XCTAssertEqual(actual.textSize, expected.textSize)
        XCTAssertEqual(actual.backgroundColor, expected.backgroundColor)
        XCTAssertEqual(actual.backgroundAlias, expected.backgroundAlias)
    }

    func testParsesMultiNodeTree() {
        var builder = RealDSStoreFixtureBuilder()
        builder.addIcon(name: "LeftLeaf.app", x: 100, y: 110)
        builder.addIcon(name: "Boundary.app", x: 200, y: 210)
        builder.addIcon(name: "RightLeafA.app", x: 300, y: 310)
        builder.addIcon(name: "RightLeafB.app", x: 400, y: 410)

        let doc = DSStoreReader.parse(builder.buildMultiNode())

        // 记录顺序为 icvp、bwsp、LeftLeaf、Boundary、RightLeafA、RightLeafB；
        // 中点记录落在内部节点，其余分属左右两个叶子。
        XCTAssertEqual(doc.iconPositions.count, 4)
        XCTAssertEqual(doc.iconPositions["LeftLeaf.app"]?.x ?? 0, 100, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["Boundary.app"]?.y ?? 0, 210, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["RightLeafA.app"]?.x ?? 0, 300, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["RightLeafB.app"]?.y ?? 0, 410, accuracy: 0.001)
        XCTAssertEqual(doc.windowFrame?.size.width ?? 0, 640, accuracy: 0.001)
        XCTAssertEqual(doc.iconSize ?? 0, 80, accuracy: 0.001)
    }

    func testCyclicTreeDoesNotHang() {
        var builder = RealDSStoreFixtureBuilder()
        builder.addIcon(name: "LeftLeaf.app", x: 10, y: 20)
        builder.addIcon(name: "Boundary.app", x: 30, y: 40)
        builder.addIcon(name: "RightLeafA.app", x: 50, y: 60)
        builder.addIcon(name: "RightLeafB.app", x: 70, y: 80)

        let doc = DSStoreReader.parse(builder.buildCyclicTree())

        // 内部节点的尾随子节点指向自身：左叶与边界记录可达，右叶永远不可达。
        XCTAssertEqual(doc.iconPositions["LeftLeaf.app"]?.x ?? 0, 10, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["Boundary.app"]?.x ?? 0, 30, accuracy: 0.001)
        XCTAssertNil(doc.iconPositions["RightLeafA.app"])
        XCTAssertNil(doc.iconPositions["RightLeafB.app"])
    }

    func testDeepChainStopsAtDepthCap() {
        let builder = RealDSStoreFixtureBuilder()
        let doc = DSStoreReader.parse(builder.buildDeepChain(nodeCount: 100))

        // levels 未知时兜底上限为 64，即处理 depth 0...63 共 64 个节点。
        XCTAssertEqual(doc.iconPositions.count, 64)
        XCTAssertNotNil(doc.iconPositions["L0"])
        XCTAssertNotNil(doc.iconPositions["L63"])
        XCTAssertNil(doc.iconPositions["L64"])
        XCTAssertNil(doc.iconPositions["Leaf"])
    }

    func testParsesNegativeIlocCoordinates() {
        var builder = RealDSStoreFixtureBuilder()
        builder.addIcon(name: "Negative.app", x: -5, y: -7)

        let doc = DSStoreReader.parse(builder.build())

        XCTAssertEqual(doc.iconPositions["Negative.app"]?.x ?? 0, -5, accuracy: 0.001)
        XCTAssertEqual(doc.iconPositions["Negative.app"]?.y ?? 0, -7, accuracy: 0.001)
    }
}
