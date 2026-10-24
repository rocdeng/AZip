import Foundation

public enum ArchiveError: LocalizedError, Sendable {
    case unsupportedFormat(String)
    case destinationNotWritable(URL)
    case toolFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFormat(ext):
            return "暂不支持解压 .\(ext) 格式"
        case .destinationNotWritable:
            return "没有权限写入解压目标文件夹"
        case let .toolFailed(message):
            return "解压失败：\(message)"
        case .cancelled:
            return "已取消解压"
        }
    }
}

public enum ArchiveExtractor {
    /// 与 `ditto` 一起使用时保留资源分支与扩展属性。
    private static let ditto = "/usr/bin/ditto"

    /// 解压 zip 到 `destination`（必须是尚不存在的目录）。
    ///
    /// 进度按“目标目录已写入字节 / 压缩包解压后总字节”估算，每 180 ms 采样一次。
    public static func extract(
        zipURL: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async throws {
        guard zipURL.pathExtension.lowercased() == "zip" else {
            throw ArchiveError.unsupportedFormat(zipURL.pathExtension.lowercased())
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

        let total = uncompressedSize(of: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ditto)
        process.arguments = ["-x", "-k", "--rsrc", zipURL.path, destination.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw ArchiveError.toolFailed(error.localizedDescription)
        }

        while process.isRunning {
            if isCancelled() {
                process.terminate()
                process.waitUntilExit()
                throw ArchiveError.cancelled
            }
            if total > 0 {
                let written = directorySize(destination)
                progress(min(0.99, Double(written) / Double(total)))
            }
            try? await Task.sleep(for: .milliseconds(180))
        }

        let errorData = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errorText = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw ArchiveError.toolFailed(
                errorText.isEmpty ? "ditto 退出码 \(process.terminationStatus)" : errorText
            )
        }
        progress(1.0)
    }

    /// 解压目标的默认位置：与压缩包同目录、同名文件夹；重名时追加序号。
    public static func defaultDestination(for zipURL: URL) -> URL {
        let parent = zipURL.deletingLastPathComponent()
        let base = zipURL.deletingPathExtension().lastPathComponent
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

    // MARK: - Helpers

    private static func uncompressedSize(of zipURL: URL) -> Int64 {
        guard let output = try? runAndCapture("/usr/bin/unzip", ["-l", zipURL.path]) else {
            return 0
        }
        // `unzip -l` 末尾形如：` 12345678                     12 files`
        for line in output.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("file") else { continue }
            let digits = trimmed.prefix { $0.isNumber }
            if let value = Int64(digits) { return value }
        }
        return 0
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

    private static func directorySize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}
