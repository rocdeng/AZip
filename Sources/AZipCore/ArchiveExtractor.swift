import Foundation
import OSLog

public enum ArchiveError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case destinationNotWritable(URL)
    case toolFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return String(format: NSLocalizedString("暂不支持解压 .%@ 格式", comment: ""), ext)
        case .destinationNotWritable:
            return NSLocalizedString("没有权限写入解压目标文件夹", comment: "")
        case let .toolFailed(message):
            return String(format: NSLocalizedString("解压失败：%@", comment: ""), message)
        case .cancelled:
            return NSLocalizedString("已取消解压", comment: "")
        }
    }
}

public enum ArchiveExtractor {
    /// 系统自带的 libarchive 前端，覆盖 zip / tar / gz / bz2 / xz / 7z / rar / iso 等。
    private static let bsdtar = "/usr/bin/bsdtar"

    /// 可交给 `bsdtar` 处理的扩展名。
    public static let supportedExtensions: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "tbz", "tbz2",
        "xz", "txz", "7z", "rar", "iso", "zst", "lz4"
    ]

    /// 复合扩展名按长度从长到短匹配，避免 `.tar.gz` 被当成 `.gz`。
    private static let knownSuffixes = [
        ".tar.gz", ".tar.bz2", ".tar.xz", ".tar.zst",
        ".tgz", ".tbz2", ".tbz", ".txz",
        ".zip", ".7z", ".rar", ".iso", ".zst", ".lz4",
        ".gz", ".bz2", ".xz", ".tar"
    ]

    public static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// 解压到 `destination`（必须是尚不存在的目录）。
    ///
    /// 进度按「目标目录已生成条目数 / 归档内条目总数」估算，每 180 ms 采样一次。
    public static func extract(
        archiveURL: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async throws {
        let ext = archiveURL.pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            throw ArchiveError.unsupportedFormat(ext)
        }

        let parent = destination.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw ArchiveError.destinationNotWritable(parent)
        }

        do {
            try FileManager.default.createDirectory(
                at: destination,
                withIntermediateDirectories: true
            )
        } catch {
            throw ArchiveError.destinationNotWritable(parent)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: bsdtar)
        process.arguments = [
            "-xf", archiveURL.path,
            "-C", destination.path,
            "--no-same-owner"
        ]
        let errorPipe = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        do {
            try process.run()
            log("bsdtar started pid=\(process.processIdentifier)")
        } catch {
            log("bsdtar launch failed: \(error)")
            throw ArchiveError.toolFailed(error.localizedDescription)
        }

        // 不读子进程输出：管道在后台任务里容易造成死锁，
        // 进度改用不确定动画在 UI 层展示。
        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                throw ArchiveError.cancelled
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        let errorData = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errorText = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        log("bsdtar exit=\(process.terminationStatus) stderr=\(errorText.prefix(300))")
        guard process.terminationStatus == 0 else {
            throw ArchiveError.toolFailed(
                errorText.isEmpty ? "bsdtar 退出码 \(process.terminationStatus)" : errorText
            )
        }
        progress(1.0)
    }

    /// 默认解压位置：与归档同目录、同名文件夹；重名时追加序号。
    public static func defaultDestination(for archiveURL: URL) -> URL {
        let parent = archiveURL.deletingLastPathComponent()
        let base = baseName(for: archiveURL)
        let candidate = parent.appendingPathComponent(base)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return candidate
        }
        for index in 2...999 {
            let numbered = parent.appendingPathComponent("\(base) \(index)")
            if !FileManager.default.fileExists(atPath: numbered.path) {
                return numbered
            }
        }
        return parent.appendingPathComponent("\(base) \(UUID().uuidString.prefix(6))")
    }

    public static func baseName(for archiveURL: URL) -> String {
        let name = archiveURL.lastPathComponent
        let lowercased = name.lowercased()
        for suffix in knownSuffixes where lowercased.hasSuffix(suffix) {
            let trimmed = String(name.dropLast(suffix.count))
            if !trimmed.isEmpty { return trimmed }
        }
        return archiveURL.deletingPathExtension().lastPathComponent
    }

    // MARK: - Helpers

    private static let logger = Logger(subsystem: "com.dengpeng.AZip", category: "extract")

    private static func log(_ line: String) {
        logger.info("\(line, privacy: .public)")
    }

    private static func countEntries(inArchive url: URL) -> Int {
        guard let output = try? runAndCapture("/usr/bin/bsdtar", ["-tf", url.path]) else {
            return 0
        }
        return output.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    private static func countFileSystemEntries(in url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        var count = 0
        for case _ as URL in enumerator {
            count += 1
        }
        return count
    }

    private static func runAndCapture(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
