import CoreGraphics
import Foundation

public struct DSStoreDocument: Sendable {
    public var windowFrame: CGRect?
    public var iconSize: CGFloat?
    public var textSize: CGFloat?
    /// 背景色分量。真实文件为 RGB 三个分量。
    public var backgroundColor: [CGFloat]?
    public var backgroundAlias: Data?
    public var iconPositions: [String: CGPoint] = [:]

    public init() {}
}

public enum DSStoreReader {
    /// `.DS_Store` 中 `Iloc` 坐标的换算系数。
    ///
    /// 实测 macOS 26 生成的 dmg 中 `Iloc` 直接存储点值（例如 448 对应 448pt），
    /// 因此系数为 1.0。
    public static let pointsPerLocationUnit: CGFloat = 1.0

    public static func parse(_ data: Data) -> DSStoreDocument {
        // 调用方可能传入切片（`dropFirst()`、`data[a..<b]`），此时 `startIndex != 0`，
        // 下面所有绝对下标都会越界。入口统一复制成从 0 开始的 Data。
        let data = Data(data)
        // Bud1 文件以 `00 00 00 01 "Bud1"` 开头。
        if data.count >= 20, readUInt32(data, at: 0) == 1,
           data[4..<8] == Data("Bud1".utf8) {
            return parseBuddyFile(data)
        }
        return DSStoreDocument()
    }

    // MARK: - Real Bud1 (buddy allocator + B-tree)

    private static func parseBuddyFile(_ data: Data) -> DSStoreDocument {
        var document = DSStoreDocument()

        let rootOffset = Int(readUInt32(data, at: 8))
        let rootSize = Int(readUInt32(data, at: 12))
        let rootOffset2 = Int(readUInt32(data, at: 16))
        guard rootOffset > 0, rootOffset == rootOffset2, rootSize > 0 else {
            return document
        }

        // buddy allocator 的所有块内容都从 offset + 4 开始。
        let rootStart = rootOffset + 4
        let rootEnd = rootStart + rootSize
        guard rootStart >= 0, rootEnd <= data.count else { return document }

        var cursor = rootStart
        guard cursor + 8 <= rootEnd else { return document }
        let blockCount = Int(readUInt32(data, at: cursor))
        cursor += 8 // 跳过 blockCount 与 unknown2

        let paddedCount = (blockCount + 255) & ~255
        guard blockCount >= 0, paddedCount >= blockCount,
              cursor + paddedCount * 4 <= rootEnd else { return document }
        var offsets: [UInt32] = []
        offsets.reserveCapacity(blockCount)
        for index in 0..<blockCount {
            offsets.append(readUInt32(data, at: cursor + index * 4))
        }
        cursor += paddedCount * 4

        guard cursor + 4 <= rootEnd else { return document }
        let tocCount = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard tocCount >= 0 else { return document }

        var superBlock: Int?
        for _ in 0..<tocCount {
            guard cursor + 1 <= rootEnd else { return document }
            let nameLength = Int(data[cursor])
            cursor += 1
            guard cursor + nameLength + 4 <= rootEnd else { return document }
            let name = String(decoding: data[cursor..<cursor + nameLength], as: UTF8.self)
            cursor += nameLength
            let blockIndex = Int(readUInt32(data, at: cursor))
            cursor += 4
            if name == "DSDB" {
                superBlock = blockIndex
            }
        }
        guard let superBlock,
              let (superStart, superEnd) = buddyBlockRange(data, offsets: offsets, index: superBlock),
              superStart + 20 <= superEnd else { return document }

        let rootNode = Int(readUInt32(data, at: superStart))
        // 超级块 offset+12 处的 levels 表示树的层数；为 0 表示未知。
        // 即使文件谎报极深层级，也钳制到常量上限，避免恶意文件造成栈溢出。
        let levelCount = Int(readUInt32(data, at: superStart + 12))
        let depthLimit = levelCount > 0 ? min(levelCount, maxTraversalDepth) : maxTraversalDepth
        var visited = Set<Int>()
        traverseBuddyTree(
            data,
            offsets: offsets,
            node: rootNode,
            depth: 0,
            depthLimit: depthLimit,
            visited: &visited,
            into: &document
        )
        return document
    }

    /// B-tree 递归深度的兜底上限，防止构造的深层文件耗尽调用栈。
    private static let maxTraversalDepth = 64

    /// 将 offset 数组中的地址解析为块内容区间 `[start, end)`。
    private static func buddyBlockRange(
        _ data: Data,
        offsets: [UInt32],
        index: Int
    ) -> (Int, Int)? {
        guard index >= 0, index < offsets.count else { return nil }
        let address = Int(offsets[index])
        guard address != 0 else { return nil }
        let offset = address & ~0x1F
        let width = address & 0x1F
        guard width > 0, width < 31 else { return nil }
        let start = offset + 4
        let end = start + (1 << width)
        guard start >= 0, end <= data.count else { return nil }
        return (start, end)
    }

    private static func traverseBuddyTree(
        _ data: Data,
        offsets: [UInt32],
        node: Int,
        depth: Int,
        depthLimit: Int,
        visited: inout Set<Int>,
        into document: inout DSStoreDocument
    ) {
        guard depth < depthLimit,
              visited.insert(node).inserted,
              let (start, end) = buddyBlockRange(data, offsets: offsets, index: node),
              start + 8 <= end else { return }

        var cursor = start
        let nextNode = Int(readUInt32(data, at: cursor))
        let recordCount = Int(readUInt32(data, at: cursor + 4))
        cursor += 8

        if nextNode != 0 {
            // 内部节点：[next | count | (ptr | record) ...]
            for _ in 0..<recordCount {
                guard cursor + 4 <= end else { return }
                let child = Int(readUInt32(data, at: cursor))
                cursor += 4
                traverseBuddyTree(
                    data,
                    offsets: offsets,
                    node: child,
                    depth: depth + 1,
                    depthLimit: depthLimit,
                    visited: &visited,
                    into: &document
                )
                guard let (record, nextCursor) = readBuddyRecord(data, at: cursor, end: end) else {
                    return
                }
                cursor = nextCursor
                applyBuddy(record, into: &document)
            }
            traverseBuddyTree(
                data,
                offsets: offsets,
                node: nextNode,
                depth: depth + 1,
                depthLimit: depthLimit,
                visited: &visited,
                into: &document
            )
        } else {
            // 叶子节点：[0 | count | record ...]
            for _ in 0..<recordCount {
                guard let (record, nextCursor) = readBuddyRecord(data, at: cursor, end: end) else {
                    return
                }
                cursor = nextCursor
                applyBuddy(record, into: &document)
            }
        }
    }

    private struct BuddyRecord {
        let name: String
        let code: String
        let type: String
        let value: Data
    }

    private static func readBuddyRecord(
        _ data: Data,
        at start: Int,
        end: Int
    ) -> (BuddyRecord, Int)? {
        var cursor = start
        guard cursor + 4 <= end else { return nil }
        let nameLength = Int(readUInt32(data, at: cursor))
        cursor += 4
        guard nameLength >= 0, cursor + nameLength * 2 + 8 <= end else { return nil }
        let name = String(data: data[cursor..<cursor + nameLength * 2], encoding: .utf16BigEndian) ?? ""
        cursor += nameLength * 2

        let code = String(data: data[cursor..<cursor + 4], encoding: .ascii) ?? ""
        cursor += 4
        let type = String(data: data[cursor..<cursor + 4], encoding: .ascii) ?? ""
        cursor += 4

        let value: Data
        switch type {
        case "bool":
            guard cursor + 1 <= end else { return nil }
            value = data[cursor..<cursor + 1]
            cursor += 1
        case "long", "shor":
            guard cursor + 4 <= end else { return nil }
            value = data[cursor..<cursor + 4]
            cursor += 4
        case "blob":
            guard cursor + 4 <= end else { return nil }
            let length = Int(readUInt32(data, at: cursor))
            cursor += 4
            guard length >= 0, cursor + length <= end else { return nil }
            value = data[cursor..<cursor + length]
            cursor += length
        case "ustr":
            guard cursor + 4 <= end else { return nil }
            let length = Int(readUInt32(data, at: cursor))
            cursor += 4
            guard length >= 0, cursor + length * 2 <= end else { return nil }
            value = data[cursor..<cursor + length * 2]
            cursor += length * 2
        case "type":
            guard cursor + 4 <= end else { return nil }
            value = data[cursor..<cursor + 4]
            cursor += 4
        case "comp", "dutc":
            guard cursor + 8 <= end else { return nil }
            value = data[cursor..<cursor + 8]
            cursor += 8
        default:
            return nil
        }

        return (BuddyRecord(name: name, code: code, type: type, value: Data(value)), cursor)
    }

    private static func applyBuddy(_ record: BuddyRecord, into document: inout DSStoreDocument) {
        switch record.code {
        case "Iloc":
            guard record.value.count >= 8 else { return }
            let x = CGFloat(Int32(bitPattern: readUInt32(record.value, at: 0))) * pointsPerLocationUnit
            let y = CGFloat(Int32(bitPattern: readUInt32(record.value, at: 4))) * pointsPerLocationUnit
            document.iconPositions[record.name] = CGPoint(x: x, y: y)

        case "icvp":
            guard let properties = propertyList(record.value) else { return }
            if let size = number(properties["iconSize"]) {
                document.iconSize = CGFloat(size)
            }
            if let size = number(properties["textSize"]) {
                document.textSize = CGFloat(size)
            }
            if let red = number(properties["backgroundColorRed"]),
               let green = number(properties["backgroundColorGreen"]),
               let blue = number(properties["backgroundColorBlue"]) {
                document.backgroundColor = [CGFloat(red), CGFloat(green), CGFloat(blue)]
            } else if let raw = properties["backgroundColor"] as? Data {
                document.backgroundColor = readColor(raw)
            }
            if let alias = properties["backgroundImageAlias"] as? Data {
                document.backgroundAlias = alias
            }

        case "bwsp":
            guard let properties = propertyList(record.value),
                  let bounds = properties["WindowBounds"] as? String,
                  let frame = parseBoundsString(bounds) else { return }
            document.windowFrame = frame

        default:
            break
        }
    }

    private static func propertyList(_ data: Data) -> [String: Any]? {
        guard let object = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) else { return nil }
        return object as? [String: Any]
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    // MARK: - Value decoding

    private static func readColor(_ data: Data) -> [CGFloat]? {
        guard data.count >= 12 else { return nil }
        let components = stride(from: 0, to: 12, by: 2).map { offset -> CGFloat in
            let raw = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            return CGFloat(raw) / 65535.0
        }
        return components
    }

    private static func parseBoundsString(_ text: String) -> CGRect? {
        let numbers = text
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.-").inverted)
            .compactMap(Double.init)
        guard numbers.count >= 4 else { return nil }
        return CGRect(
            x: numbers[0], y: numbers[1],
            width: numbers[2], height: numbers[3]
        )
    }

    // MARK: - Byte helpers

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset]) << 24
            | UInt32(data[offset + 1]) << 16
            | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }
}
