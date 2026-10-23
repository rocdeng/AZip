import Foundation

/// 构造真实格式的 Bud1 文件：buddy allocator 头部 + 根块/TOC + B-tree 节点，
/// `icvp` / `bwsp` 使用二进制 plist，与 macOS 实际写法一致。
///
/// B-tree 节点结构假设（与 `DSStoreReader.traverseBuddyTree` 的约定一致）：
/// - 节点头部为 `next(4) + count(4)`；
/// - 叶子节点 `next == 0`，主体为 `count` 条记录；
/// - 内部节点 `next` 保存“尾随子节点”的 offset 表索引，主体为
///   `count` 组 `(child 索引, record)`，读取顺序为先子节点、后记录，
///   最后再遍历 `next` 指向的子节点。
struct RealDSStoreFixtureBuilder {
    private typealias Record = (name: String, code: String, value: Data)

    private struct BlockSpec {
        let address: Int
        let width: Int
        let content: Data
    }

    private var icons: [(name: String, x: Int, y: Int)] = []

    var iconSize: Double = 80
    var textSize: Double = 12
    var backgroundColor: (red: Double, green: Double, blue: Double)? = (1, 1, 1)
    var backgroundAlias: Data?
    var windowBounds = "{64, 64}, {640, 400}"

    mutating func addIcon(name: String, x: Int, y: Int) {
        icons.append((name: name, x: x, y: y))
    }

    /// 单叶子节点（现有测试使用）。
    func build() -> Data {
        let records = buildRecords()
        let leaf = BlockSpec(address: 0x1000, width: 10, content: leafNode(records))
        return makeFile(levels: 1, rootNodeIndex: 2, recordCount: records.count, nodes: [leaf])
    }

    /// 一个内部节点 + 两个叶子节点。记录按中点拆分：
    /// 前半在左叶、中点记录在内部节点、后半在右叶。
    func buildMultiNode() -> Data {
        let records = buildRecords()
        let mid = records.count / 2
        let leftRecords = Array(records[..<mid])
        let boundary = records[mid]
        let rightRecords = Array(records[(mid + 1)...])

        // offset 表索引：0 = 根块，1 = 超级块，2 = 左叶，3 = 内部节点，4 = 右叶。
        let leaf1 = BlockSpec(address: 0x1000, width: 10, content: leafNode(leftRecords))
        let internalBlock = BlockSpec(
            address: 0x2000,
            width: 11,
            content: internalNode(next: 4, entries: [(child: 2, record: boundary)])
        )
        let leaf2 = BlockSpec(address: 0x3000, width: 10, content: leafNode(rightRecords))
        return makeFile(
            levels: 2,
            rootNodeIndex: 3,
            recordCount: records.count,
            nodes: [leaf1, internalBlock, leaf2]
        )
    }

    /// 与 `buildMultiNode()` 相同的两块叶子，但内部节点的尾随子节点指向自身。
    /// 右叶因此永远不可达；用于验证遍历不会因环而无限递归。
    func buildCyclicTree() -> Data {
        let records = buildRecords()
        let mid = records.count / 2
        let boundary = records[mid]

        let leaf1 = BlockSpec(
            address: 0x1000,
            width: 10,
            content: leafNode(Array(records[..<mid]))
        )
        let internalBlock = BlockSpec(
            address: 0x2000,
            width: 11,
            content: internalNode(next: 3, entries: [(child: 2, record: boundary)])
        )
        let leaf2 = BlockSpec(
            address: 0x3000,
            width: 10,
            content: leafNode(Array(records[(mid + 1)...]))
        )
        return makeFile(
            levels: 2,
            rootNodeIndex: 3,
            recordCount: records.count,
            nodes: [leaf1, internalBlock, leaf2]
        )
    }

    /// 一条由 `nodeCount - 1` 个内部节点组成的链，末端一个叶子节点。
    /// 超级块的 levels 写 0（未知），用于覆盖解析器的深度兜底上限。
    func buildDeepChain(nodeCount: Int) -> Data {
        precondition(nodeCount >= 2)
        var nodes: [BlockSpec] = []
        for index in 0..<nodeCount {
            let address = 0x4000 + index * 0x800
            let content: Data
            if index == nodeCount - 1 {
                content = leafNode([
                    ("Leaf", "Iloc", ilocValue(x: 999, y: 999)),
                ])
            } else {
                let child = 2 + index + 1 // offset 表索引：0 = 根块，1 = 超级块。
                content = internalNode(
                    next: child,
                    entries: [(child: child, record: ("L\(index)", "Iloc", ilocValue(x: index, y: index)))]
                )
            }
            nodes.append(BlockSpec(address: address, width: 10, content: content))
        }
        return makeFile(levels: 0, rootNodeIndex: 2, recordCount: nodeCount, nodes: nodes)
    }

    // MARK: - File layout

    private func makeFile(
        levels: Int,
        rootNodeIndex: Int,
        recordCount: Int,
        nodes: [BlockSpec]
    ) -> Data {
        let rootAddress = 0x800
        let rootWidth = 11
        let superAddress = 0x40
        let superWidth = 5

        let entries = [rootAddress | rootWidth, superAddress | superWidth]
            + nodes.map { $0.address | $0.width }
        let blockCount = entries.count
        let paddedCount = (blockCount + 255) & ~255

        // 根块：块数、unknown、offset 数组（补齐到 256 项）、TOC、空 free list。
        var root = Data()
        root.append(beUInt32(UInt32(blockCount)))
        root.append(beUInt32(0))
        for entry in entries {
            root.append(beUInt32(UInt32(entry)))
        }
        root.append(Data(count: (paddedCount - blockCount) * 4))
        root.append(beUInt32(1)) // TOC 项数
        root.append(UInt8(4))
        root.append(Data("DSDB".utf8))
        root.append(beUInt32(1)) // DSDB 位于 offset 表索引 1
        root.append(Data(count: 32 * 4))

        // DSDB 超级块：rootnode、records、levels、page size。
        var superBlock = Data()
        superBlock.append(beUInt32(UInt32(rootNodeIndex)))
        superBlock.append(beUInt32(0))
        superBlock.append(beUInt32(UInt32(recordCount)))
        superBlock.append(beUInt32(UInt32(levels)))
        superBlock.append(beUInt32(4096))

        let totalSize = max(
            rootAddress + 4 + root.count,
            max(
                superAddress + 4 + superBlock.count,
                nodes.map { $0.address + 4 + (1 << $0.width) }.max() ?? 0
            )
        )

        var data = Data(count: totalSize)

        // 文件头：01 00 00 00 + "Bud1" + root offset/size/offset。
        write(beUInt32(1), at: 0, into: &data)
        write(Data("Bud1".utf8), at: 4, into: &data)
        write(beUInt32(UInt32(rootAddress)), at: 8, into: &data)
        write(beUInt32(UInt32(1 << rootWidth)), at: 12, into: &data)
        write(beUInt32(UInt32(rootAddress)), at: 16, into: &data)

        write(root, at: rootAddress + 4, into: &data)
        write(superBlock, at: superAddress + 4, into: &data)
        for node in nodes {
            write(node.content, at: node.address + 4, into: &data)
        }
        return data
    }

    private func leafNode(_ records: [Record]) -> Data {
        var node = Data()
        node.append(beUInt32(0))
        node.append(beUInt32(UInt32(records.count)))
        for record in records {
            node.append(encodeRecord(record))
        }
        return node
    }

    private func internalNode(next: Int, entries: [(child: Int, record: Record)]) -> Data {
        var node = Data()
        node.append(beUInt32(UInt32(next)))
        node.append(beUInt32(UInt32(entries.count)))
        for entry in entries {
            node.append(beUInt32(UInt32(entry.child)))
            node.append(encodeRecord(entry.record))
        }
        return node
    }

    // MARK: - Records

    private func buildRecords() -> [Record] {
        var records: [Record] = []

        if let icvp = makePlist(icvpProperties()) {
            records.append((".", "icvp", icvp))
        }
        if let bwsp = makePlist(["WindowBounds": "{{\(windowBounds)}}"]) {
            records.append((".", "bwsp", bwsp))
        }
        for icon in icons {
            records.append((icon.name, "Iloc", ilocValue(x: icon.x, y: icon.y)))
        }
        return records
    }

    private func ilocValue(x: Int, y: Int) -> Data {
        var value = Data()
        value.append(beUInt32(UInt32(bitPattern: Int32(x))))
        value.append(beUInt32(UInt32(bitPattern: Int32(y))))
        value.append(beUInt32(0xFFFF_FFFF))
        value.append(beUInt32(0xFFFF_0000))
        return value
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

    private func encodeRecord(_ record: Record) -> Data {
        var data = Data()
        data.append(beUInt32(UInt32(record.name.utf16.count)))
        for unit in record.name.utf16 {
            data.append(UInt8(unit >> 8))
            data.append(UInt8(unit & 0xFF))
        }
        data.append(Data(record.code.utf8))
        data.append(Data("blob".utf8))
        data.append(beUInt32(UInt32(record.value.count)))
        data.append(record.value)
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
