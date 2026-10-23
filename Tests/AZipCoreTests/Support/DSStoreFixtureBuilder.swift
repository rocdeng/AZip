import Foundation

/// 构造最小可解析的 Bud1 文件，用于单测。
struct DSStoreFixtureBuilder {
    private var records: [(name: String, code: String, type: String, value: Data)] = []

    mutating func addICVP(iconSize: Double, textSize: Double, backgroundColor: [UInt8]?) {
        var payload = Data()
        payload.append(field(code: "icon", type: "doub", value: doubleData(iconSize)))
        payload.append(field(code: "text", type: "doub", value: doubleData(textSize)))
        if let backgroundColor {
            payload.append(field(code: "bkgd", type: "blob", value: Data(backgroundColor)))
        }
        records.append((name: ".", code: "icvp", type: "blob", value: payload))
    }

    mutating func addBWSP(width: Double, height: Double) {
        let bounds = "{64, 64}, {\(Int(width)), \(Int(height))}"
        var payload = Data()
        payload.append(field(code: "wndb", type: "type", value: utf16beData(bounds)))
        records.append((name: ".", code: "bwsp", type: "blob", value: payload))
    }

    mutating func addIcon(name: String, x: Int, y: Int) {
        var value = Data()
        value.append(beUInt32(UInt32(x)))
        value.append(beUInt32(UInt32(y)))
        records.append((name: name, code: "Iloc", type: "blob", value: value))
    }

    func build() -> Data {
        var block = Data()
        block.append(beUInt32(0)) // next block offset = 0
        for record in records {
            let nameData = utf16beData(record.name)
            block.append(beUInt32(UInt32(nameData.count / 2)))
            block.append(nameData)
            block.append(Data(record.code.utf8))
            block.append(Data(record.type.utf8))
            block.append(beUInt32(UInt32(record.value.count)))
            block.append(record.value)
        }
        block.append(beUInt32(0)) // 结束标记：filename length == 0

        let rootOffset = 0x1000
        var data = Data("Bud1".utf8)
        data.append(beUInt32(UInt32(rootOffset)))
        data.append(Data(count: 256)) // block 索引表留空
        if data.count < rootOffset {
            data.append(Data(count: rootOffset - data.count))
        }
        data.append(block)
        return data
    }

    // MARK: - Helpers

    private func field(code: String, type: String, value: Data) -> Data {
        var data = Data()
        data.append(Data(code.utf8))
        data.append(Data(type.utf8))
        data.append(beUInt32(UInt32(value.count)))
        data.append(value)
        return data
    }

    private func beUInt32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private func doubleData(_ value: Double) -> Data {
        withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) }
    }

    private func utf16beData(_ string: String) -> Data {
        var data = Data()
        for unit in string.utf16 {
            data.append(UInt8(unit >> 8))
            data.append(UInt8(unit & 0xFF))
        }
        return data
    }
}

/// 构造真实格式的 Bud1 文件：buddy allocator 头部 + 根块/TOC + B-tree 叶子节点，
/// `icvp` / `bwsp` 使用二进制 plist，与 macOS 实际写法一致。
struct RealDSStoreFixtureBuilder {
    private var icons: [(name: String, x: Int, y: Int)] = []

    var iconSize: Double = 80
    var textSize: Double = 12
    var backgroundColor: (red: Double, green: Double, blue: Double)? = (1, 1, 1)
    var backgroundAlias: Data?
    var windowBounds = "{64, 64}, {640, 400}"

    mutating func addIcon(name: String, x: Int, y: Int) {
        icons.append((name: name, x: x, y: y))
    }

    func build() -> Data {
        let rootOffset = 0x800
        let rootSize = 2048
        let superOffset = 0x40
        let leafOffset = 0x1000
        let leafSize = 1024

        var data = Data(count: leafOffset + 4 + leafSize)

        // 文件头：01 00 00 00 + "Bud1" + root offset/size/offset。
        write(beUInt32(1), at: 0, into: &data)
        write(Data("Bud1".utf8), at: 4, into: &data)
        write(beUInt32(UInt32(rootOffset)), at: 8, into: &data)
        write(beUInt32(UInt32(rootSize)), at: 12, into: &data)
        write(beUInt32(UInt32(rootOffset)), at: 16, into: &data)

        let records = buildRecords()

        // 根块：块数、unknown、offset 数组（补齐到 256 项）、TOC、空 free list。
        var root = Data()
        root.append(beUInt32(3))
        root.append(beUInt32(0))
        root.append(beUInt32(UInt32(rootOffset | 11)))
        root.append(beUInt32(UInt32(superOffset | 5)))
        root.append(beUInt32(UInt32(leafOffset | 10)))
        root.append(Data(count: (256 - 3) * 4))
        root.append(beUInt32(1))
        root.append(UInt8(4))
        root.append(Data("DSDB".utf8))
        root.append(beUInt32(1))
        root.append(Data(count: 32 * 4))
        write(root, at: rootOffset + 4, into: &data)

        // DSDB 超级块：rootnode、levels、records、nodes、page size。
        var superBlock = Data()
        superBlock.append(beUInt32(2))
        superBlock.append(beUInt32(0))
        superBlock.append(beUInt32(UInt32(records.count)))
        superBlock.append(beUInt32(1))
        superBlock.append(beUInt32(4096))
        write(superBlock, at: superOffset + 4, into: &data)

        // B-tree 叶子节点：[0 | count | record ...]。
        var leaf = Data()
        leaf.append(beUInt32(0))
        leaf.append(beUInt32(UInt32(records.count)))
        for record in records {
            leaf.append(encodeRecord(name: record.name, code: record.code, value: record.value))
        }
        write(leaf, at: leafOffset + 4, into: &data)

        return data
    }

    // MARK: - Records

    private func buildRecords() -> [(name: String, code: String, value: Data)] {
        var records: [(name: String, code: String, value: Data)] = []

        if let icvp = makePlist(icvpProperties()) {
            records.append((name: ".", code: "icvp", value: icvp))
        }
        if let bwsp = makePlist(["WindowBounds": "{{\(windowBounds)}}"]) {
            records.append((name: ".", code: "bwsp", value: bwsp))
        }
        for icon in icons {
            var value = Data()
            value.append(beUInt32(UInt32(icon.x)))
            value.append(beUInt32(UInt32(icon.y)))
            value.append(beUInt32(0xFFFF_FFFF))
            value.append(beUInt32(0xFFFF_0000))
            records.append((name: icon.name, code: "Iloc", value: value))
        }
        return records
    }

    private func icvpProperties() -> [String: Any] {
        var properties: [String: Any] = [
            "iconSize": iconSize,
            "textSize": textSize,
            "backgroundType": backgroundAlias == nil ? 1 : 2,
        ]
        if let backgroundColor {
            properties["backgroundColorRed"] = backgroundColor.red
            properties["backgroundColorGreen"] = backgroundColor.green
            properties["backgroundColorBlue"] = backgroundColor.blue
        }
        if let backgroundAlias {
            properties["backgroundImageAlias"] = backgroundAlias
        }
        return properties
    }

    private func makePlist(_ object: [String: Any]) -> Data? {
        try? PropertyListSerialization.data(
            fromPropertyList: object,
            format: .binary,
            options: 0
        )
    }

    private func encodeRecord(name: String, code: String, value: Data) -> Data {
        var data = Data()
        data.append(beUInt32(UInt32(name.utf16.count)))
        for unit in name.utf16 {
            data.append(UInt8(unit >> 8))
            data.append(UInt8(unit & 0xFF))
        }
        data.append(Data(code.utf8))
        data.append(Data("blob".utf8))
        data.append(beUInt32(UInt32(value.count)))
        data.append(value)
        return data
    }

    // MARK: - Helpers

    private func write(_ source: Data, at offset: Int, into data: inout Data) {
        guard offset >= 0, offset + source.count <= data.count else { return }
        data.replaceSubrange(offset..<offset + source.count, with: source)
    }

    private func beUInt32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }
}
