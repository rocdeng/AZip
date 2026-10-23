import Foundation

public struct InstallRequest: Sendable {
    public let sourceApp: URL
    public let targetDirectory: URL
    public let overwrite: Bool
    public let trashHandler: @Sendable (URL) -> Bool

    public init(
        sourceApp: URL,
        targetDirectory: URL,
        overwrite: Bool,
        trashHandler: @escaping @Sendable (URL) -> Bool = AppInstaller.moveToTrash
    ) {
        self.sourceApp = sourceApp
        self.targetDirectory = targetDirectory
        self.overwrite = overwrite
        self.trashHandler = trashHandler
    }
}

public enum InstallError: Error, Sendable {
    case invalidSource(URL)
    case targetNotWritable(URL)
    case conflict(URL)
    case copyFailed(String)
    case moveFailed(String)
}

public enum AppInstaller {
    public static let stagingPrefix = ".azip-staging-"
    public static let backupPrefix = ".azip-backup-"

    public static func install(
        _ request: InstallRequest,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> URL {
        let fileManager = FileManager.default
        let source = request.sourceApp

        let isDirectory = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        guard source.pathExtension.lowercased() == "app", isDirectory else {
            throw InstallError.invalidSource(source)
        }

        let targetDirectory = request.targetDirectory
        guard fileManager.isWritableFile(atPath: targetDirectory.path) else {
            throw InstallError.targetNotWritable(targetDirectory)
        }

        let finalURL = targetDirectory.appendingPathComponent(source.lastPathComponent)
        if fileManager.fileExists(atPath: finalURL.path), !request.overwrite {
            throw InstallError.conflict(finalURL)
        }

        let stagingRoot = targetDirectory
            .appendingPathComponent("\(stagingPrefix)\(UUID().uuidString)")
        let stagingApp = stagingRoot.appendingPathComponent(source.lastPathComponent)

        do {
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)

            let totalBytes = directorySize(source)
            let progressTask = Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    let copied = directorySize(stagingApp)
                    if totalBytes > 0 {
                        progress(min(1.0, Double(copied) / Double(totalBytes)))
                    }
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            defer { progressTask.cancel() }

            let copy = try await ProcessRunner.run(
                "/usr/bin/ditto",
                ["--rsrc", "--extattr", "--acl", source.path, stagingApp.path],
                timeoutSeconds: 900
            )
            progressTask.cancel()
            guard copy.status == 0 else {
                throw InstallError.copyFailed(copy.stderr.isEmpty ? "ditto 退出码 \(copy.status)" : copy.stderr)
            }
            progress(1.0)

            var backupURL: URL?
            if fileManager.fileExists(atPath: finalURL.path) {
                let backup = targetDirectory
                    .appendingPathComponent("\(backupPrefix)\(UUID().uuidString).app")
                try fileManager.moveItem(at: finalURL, to: backup)
                backupURL = backup
            }

            do {
                try fileManager.moveItem(at: stagingApp, to: finalURL)
            } catch {
                if let backupURL {
                    try? fileManager.moveItem(at: backupURL, to: finalURL)
                }
                throw InstallError.moveFailed(error.localizedDescription)
            }

            _ = QuarantineCleaner.remove(at: finalURL)
            await LaunchServicesRegistrar.register(finalURL)

            if let backupURL {
                _ = request.trashHandler(backupURL)
            }

            try? fileManager.removeItem(at: stagingRoot)
            return finalURL
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    public static func pendingBackups(in targetDirectory: URL) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: targetDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.lastPathComponent.hasPrefix(backupPrefix) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// 移入废纸篓（可恢复），不使用删除。
    public static func moveToTrash(_ url: URL) -> Bool {
        var resulting: NSURL?
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private

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
