import Foundation

/// 压缩包内的一个条目。
public struct ArchiveEntry: Identifiable, Sendable, Hashable {
    /// 归档内的完整相对路径（不含开头的 `./`）。
    public let path: String
    public let isDirectory: Bool
    public let size: Int64
    public let modified: Date?

    public var id: String { path }
    /// 最后一段名字。
    public var name: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        return (trimmed as NSString).lastPathComponent
    }
    /// 所在目录（根为 ""）。
    public var parentPath: String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let parent = (trimmed as NSString).deletingLastPathComponent
        return parent == "." ? "" : parent
    }

    public init(path: String, isDirectory: Bool, size: Int64, modified: Date?) {
        self.path = path
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
    }
}

public enum ArchiveReader {
    private static let bsdtar = "/usr/bin/bsdtar"

    /// 列出归档内的全部条目（不含隐藏的 `./` 前缀干扰项）。
    public static func list(_ archiveURL: URL) async throws -> [ArchiveEntry] {
        let result = try await ProcessRunner.run(
            bsdtar,
            ["-tvf", archiveURL.path],
            environment: ["LC_ALL": "C", "LANG": "C"],
            timeoutSeconds: 120
        )
        guard result.status == 0 else {
            throw ArchiveError.toolFailed(result.stderr)
        }
        return synthesizeMissingDirectories(parseListing(result.stdout))
    }

    /// 把单个条目解压到指定目录，返回解压后的 URL。
    public static func extract(
        entry: ArchiveEntry,
        from archiveURL: URL,
        to directory: URL
    ) async throws -> URL {
        let result = try await ProcessRunner.run(
            bsdtar,
            ["-xf", archiveURL.path, "-C", directory.path, entry.path],
            environment: ["LC_ALL": "C", "LANG": "C"],
            timeoutSeconds: 300
        )
        guard result.status == 0 else {
            throw ArchiveError.toolFailed(result.stderr)
        }
        return directory.appendingPathComponent(entry.path)
    }

    /// 部分工具打包时不会写入目录条目（例如 `zip -X` 或某些构建产物），
    /// 这里根据文件路径反推并补全缺失的目录，否则根目录会显示为空。
    static func synthesizeMissingDirectories(_ entries: [ArchiveEntry]) -> [ArchiveEntry] {
        var result = entries
        var known = Set(entries.map { $0.path.hasSuffix("/") ? String($0.path.dropLast()) : $0.path })

        for entry in entries {
            var parent = entry.parentPath
            while !parent.isEmpty {
                if !known.contains(parent) {
                    let path = parent + "/"
                    result.append(
                        ArchiveEntry(path: path, isDirectory: true, size: 0, modified: nil)
                    )
                    known.insert(parent)
                }
                let next = (parent as NSString).deletingLastPathComponent
                parent = (next == "." || next == parent) ? "" : next
            }
        }
        return result
    }

    /// 解析 `bsdtar -tvf` 的输出。
    ///
    /// 形如：`-rw-r--r--  0 0 0 1234 Jan  1 12:00 folder/file.txt`
    public static func parseListing(_ text: String) -> [ArchiveEntry] {
        var entries: [ArchiveEntry] = []
        for line in text.split(separator: "\n") {
            // 前 8 段是元数据，第 9 段起是路径（可能含空格）。
            let parts = line.split(
                separator: " ",
                maxSplits: 8,
                omittingEmptySubsequences: true
            )
            guard parts.count == 9 else { continue }

            let permission = parts[0]
            let isDirectory = permission.hasPrefix("d")
            let size = Int64(parts[4]) ?? 0
            let dateText = parts[5...7].joined(separator: " ")
            var path = String(parts[8])
            if path.hasPrefix("./") { path.removeFirst(2) }
            if path.isEmpty || path == "." { continue }

            entries.append(
                ArchiveEntry(
                    path: path,
                    isDirectory: isDirectory,
                    size: size,
                    modified: parseDate(dateText)
                )
            )
        }
        return entries
    }

    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in ["MMM d HH:mm", "MMM d yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                return date
            }
        }
        return nil
    }
}
