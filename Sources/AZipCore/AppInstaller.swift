import Foundation

public struct InstallRequest: Sendable {
    public let sourceApp: URL
    public let targetDirectory: URL
    public let overwrite: Bool
    public let trashHandler: @Sendable (URL) -> Bool
    public let registerHandler: @Sendable (URL) async -> Void

    public init(
        sourceApp: URL,
        targetDirectory: URL,
        overwrite: Bool,
        trashHandler: @escaping @Sendable (URL) -> Bool = AppInstaller.moveToTrash,
        registerHandler: @escaping @Sendable (URL) async -> Void = AppInstaller.defaultRegister
    ) {
        self.sourceApp = sourceApp
        self.targetDirectory = targetDirectory
        self.overwrite = overwrite
        self.trashHandler = trashHandler
        self.registerHandler = registerHandler
    }
}

public enum InstallError: Error, Sendable {
    case invalidSource(URL)
    case targetNotWritable(URL)
    case conflict(URL)
    case copyFailed(String)
    case cancelled
    case moveFailed(String)
}

public enum AppInstaller {
    public static let stagingPrefix = ".azip-staging-"
    public static let backupPrefix = ".azip-backup-"

    public static func install(
        _ request: InstallRequest,
        progress: @escaping @Sendable (Double) -> Void = { _ in },
        isCancelled: @escaping @Sendable () -> Bool = { false }
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

            // 用可终止的进程跑 ditto，让用户可以取消安装。
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["--rsrc", "--extattr", "--acl", source.path, stagingApp.path]
            let errorPipe = Pipe()
            ditto.standardError = errorPipe
            ditto.standardOutput = FileHandle.nullDevice
            do {
                try ditto.run()
            } catch {
                progressTask.cancel()
                await progressTask.value
                throw InstallError.copyFailed(error.localizedDescription)
            }

            while ditto.isRunning {
                if isCancelled() {
                    ditto.terminate()
                    ditto.waitUntilExit()
                    progressTask.cancel()
                    await progressTask.value
                    throw InstallError.cancelled
                }
                try? await Task.sleep(for: .milliseconds(150))
            }

            progressTask.cancel()
            await progressTask.value

            guard ditto.terminationStatus == 0 else {
                let data = (try? errorPipe.fileHandleForReading.readToEnd()) ?? Data()
                let text = String(decoding: data, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                throw InstallError.copyFailed(
                    text.isEmpty
                        ? String(format: NSLocalizedString("ditto 退出码 %d", comment: ""), ditto.terminationStatus)
                        : text
                )
            }
            progress(1.0)

            let installed = try commitStaged(
                stagingApp: stagingApp,
                finalURL: finalURL,
                targetDirectory: targetDirectory,
                overwrite: request.overwrite,
                trashHandler: request.trashHandler
            )

            _ = QuarantineCleaner.remove(at: installed)
            await request.registerHandler(installed)

            try? fileManager.removeItem(at: stagingRoot)
            return installed
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            throw error
        }
    }

    /// 将已复制完成的暂存应用提交到最终位置。
    ///
    /// 提交前会重新检查目标路径是否存在：`ditto` 可能耗时很久，期间目标可能被
    /// 其他进程或用户创建。此时若未获得覆盖确认，必须抛出冲突并保持现有应用不变。
    static func commitStaged(
        stagingApp: URL,
        finalURL: URL,
        targetDirectory: URL,
        overwrite: Bool,
        trashHandler: @Sendable (URL) -> Bool
    ) throws -> URL {
        let fileManager = FileManager.default

        var backupURL: URL?
        if fileManager.fileExists(atPath: finalURL.path) {
            guard overwrite else {
                throw InstallError.conflict(finalURL)
            }
            let backup = targetDirectory
                .appendingPathComponent("\(backupPrefix)\(UUID().uuidString).app")
            try fileManager.moveItem(at: finalURL, to: backup)
            backupURL = backup
        }

        do {
            try fileManager.moveItem(at: stagingApp, to: finalURL)
        } catch {
            if let backupURL {
                do {
                    try fileManager.moveItem(at: backupURL, to: finalURL)
                } catch let restoreError {
                    // 回滚也失败：保留备份并明确告知其绝对路径，便于用户找回旧版本。
                    throw InstallError.moveFailed(
                        String(
                            format: NSLocalizedString("无法安装到 %@：%@；且无法从备份 %@ 回滚：%@", comment: ""),
                            finalURL.path,
                            error.localizedDescription,
                            backupURL.path,
                            restoreError.localizedDescription
                        )
                    )
                }
            }
            throw InstallError.moveFailed(error.localizedDescription)
        }

        if let backupURL {
            _ = trashHandler(backupURL)
        }

        return finalURL
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

    public static func defaultRegister(_ url: URL) async {
        await LaunchServicesRegistrar.register(url)
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
