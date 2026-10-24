import Foundation

public struct VolumeEntry: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable {
        case folder
        case application
        case symbolicLink
        case file
    }

    public let id: URL
    public let url: URL
    public let name: String
    public let kind: Kind
    public let byteSize: Int64?
    public let isHidden: Bool

    public init(
        url: URL,
        kind: Kind,
        byteSize: Int64?,
        isHidden: Bool
    ) {
        self.id = url
        self.url = url
        self.name = url.lastPathComponent
        self.kind = kind
        self.byteSize = byteSize
        self.isHidden = isHidden
    }
}

public enum VolumeScanner {
    public static let ignoredNames: Set<String> = [
        ".DS_Store",
        ".background",
        ".VolumeIcon.icns",
        ".fseventsd",
        ".Trashes",
        ".Spotlight-V100",
        ".TemporaryItems",
        ".com.apple.timemachine.donotpresent"
    ]

    public static func scan(directory: URL) throws -> [VolumeEntry] {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .isHiddenKey,
            .fileAllocatedSizeKey,
            .fileSizeKey,
            .nameKey
        ]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: []
        )

        var entries: [VolumeEntry] = []
        for url in urls {
            let name = url.lastPathComponent
            // 隐藏条目（`.DS_Store`、`.background.tiff` 等）一律不展示：
            // 它们是 Finder/DMG 的元数据，不是用户要安装或浏览的内容。
            if name.hasPrefix(".") || ignoredNames.contains(name) { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            let isSymbolicLink = values?.isSymbolicLink ?? false

            if isSymbolicLink {
                // 保留符号链接（典型是 DMG 里的 Applications 快捷方式）：
                // 原生窗口里它是有图标的投放目标，过滤掉会留下一个空白方块。
                // 它永远不是 `.application`，所以不会出现在可安装列表里。
                entries.append(
                    VolumeEntry(url: url, kind: .symbolicLink, byteSize: nil, isHidden: values?.isHidden ?? false)
                )
                continue
            }

            let isDirectory = values?.isDirectory ?? false
            let kind: VolumeEntry.Kind
            if isDirectory {
                kind = url.pathExtension.lowercased() == "app" ? .application : .folder
            } else {
                kind = .file
            }

            let size: Int64? = isDirectory
                ? nil
                : Int64(values?.fileSize ?? values?.fileAllocatedSize ?? 0)

            entries.append(
                VolumeEntry(url: url, kind: kind, byteSize: size, isHidden: values?.isHidden ?? false)
            )
        }

        return entries.sorted { lhs, rhs in
            let lhsRank = rank(lhs.kind)
            let rhsRank = rank(rhs.kind)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public static func applications(in entries: [VolumeEntry]) -> [VolumeEntry] {
        entries.filter { $0.kind == .application }
    }

    private static func rank(_ kind: VolumeEntry.Kind) -> Int {
        switch kind {
        case .application: return 0
        case .folder: return 1
        case .file: return 2
        case .symbolicLink: return 3
        }
    }
}
