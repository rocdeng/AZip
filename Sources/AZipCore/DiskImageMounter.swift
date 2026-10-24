import Foundation

public struct MountResult: Sendable, Equatable {
    public let mountPoint: URL
    public let deviceEntry: String
    public let volumeName: String

    public init(mountPoint: URL, deviceEntry: String, volumeName: String) {
        self.mountPoint = mountPoint
        self.deviceEntry = deviceEntry
        self.volumeName = volumeName
    }
}

public enum MountError: Error, Sendable {
    case toolFailed(code: Int32, message: String)
    case noMountPointFound
}

public enum DiskImageMounter {
    private static let hdiutil = "/usr/bin/hdiutil"

    /// 快速检查文件头是否带有 Apple 加密磁盘映像魔数（`encrcdsa` / `cdsaencr`）。
    public static func hasEncryptedMagic(_ dmgURL: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: dmgURL) else { return false }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 8), head.count == 8 else { return false }
        return head == Data("encrcdsa".utf8) || head == Data("cdsaencr".utf8)
    }

    /// 是否为加密映像（需要密码才能挂载）。
    public static func isEncrypted(_ dmgURL: URL) async -> Bool {
        if hasEncryptedMagic(dmgURL) {
            return true
        }
        guard let result = try? await ProcessRunner.run(
            hdiutil, ["isencrypted", dmgURL.path], timeoutSeconds: 20
        ) else {
            return false
        }
        return result.stdout.contains("encrypted: YES")
    }

    /// 构造传给 `hdiutil attach` 的标准输入字节流：
    /// - `hdiutil -stdinpass` 从 `fd 0` 逐字节读取口令，**仅以 `\0`（NUL）或 EOF 结束**，不以 `\n` 结束；
    /// - 若 DMG 同时带有软件许可协议（SLA，如第三方站点塞入的弹窗说明），`hdiutil` 解密后会继续从
    ///   `fd 0` 读取 1 字节回答 `Agree Y/N? `。若此时已到 EOF，就会直接返回 `attach canceled`；
    /// - 因此口令后必须紧跟 `\0Y\n`（未加密映像也传 `Y\n` 以自动同意可能存在的 SLA）。
    public static func makeHdiutilStandardInput(password: String?) -> String {
        if let password {
            return "\(password)\0Y\n"
        }
        return "Y\n"
    }

    public static func attach(_ dmgURL: URL, password: String? = nil) async throws -> MountResult {
        // 必须使用 `hdiutil attach`（且不能加 `-quiet`）：
        // 1. `diskutil image attach` 不支持含 UDIF 软件许可协议（SLA）的映像，会直接报 `attach canceled`；
        // 2. `hdiutil attach` 若加了 `-quiet`，遇到 SLA 时会尝试打开 `/dev/tty`，在 GUI 进程中因无控制终端
        //    直接返回 `attach canceled`；不加 `-quiet` 时则会从 stdin 读取 `Y\n` 自动同意协议。
        var arguments = [
            "attach", dmgURL.path, "-plist", "-nobrowse", "-noautoopen", "-readonly", "-noverify"
        ]
        if password != nil {
            arguments.append("-stdinpass")
        }
        let result = try await ProcessRunner.run(
            hdiutil,
            arguments,
            standardInput: makeHdiutilStandardInput(password: password),
            timeoutSeconds: 120
        )
        guard result.status == 0 else {
            throw MountError.toolFailed(code: result.status, message: result.stderr)
        }
        return try parseAttachOutput(Data(result.stdout.utf8))
    }

    public static func detach(_ result: MountResult) async throws {
        // 首次尝试无论是非零退出还是抛出（例如超时），都视为失败并继续尝试 `-force`；
        // 否则卷正忙时普通退出超时会让强制退出永远没有机会执行。
        let firstFailure: String
        do {
            let plain = try await ProcessRunner.run(
                hdiutil, ["detach", result.deviceEntry], timeoutSeconds: 30
            )
            if plain.status == 0 { return }
            firstFailure = String(
                format: NSLocalizedString("退出码 %d：%@", comment: ""),
                plain.status,
                plain.stderr
            )
        } catch {
            firstFailure = "\(error)"
        }

        let forcedFailure: String
        let forcedStatus: Int32
        do {
            let forced = try await ProcessRunner.run(
                hdiutil, ["detach", result.deviceEntry, "-force"], timeoutSeconds: 30
            )
            if forced.status == 0 { return }
            forcedStatus = forced.status
            forcedFailure = String(
                format: NSLocalizedString("退出码 %d：%@", comment: ""),
                forced.status,
                forced.stderr
            )
        } catch {
            forcedStatus = -1
            forcedFailure = "\(error)"
        }

        throw MountError.toolFailed(
            code: forcedStatus,
            message: String(
                format: NSLocalizedString("普通退出失败（%@）；强制退出失败（%@）", comment: ""),
                firstFailure,
                forcedFailure
            )
        )
    }

    public static func parseAttachOutput(_ data: Data) throws -> MountResult {
        // 带有 SLA（软件许可协议）的 dmg 在挂载时，hdiutil 会先把协议正文与 "Agree Y/N?"
        // 打到 stdout，随后才输出 XML plist；从第一个 "<?xml" 起截取即可。
        var payload = data
        if let text = String(data: data, encoding: .utf8),
           let range = text.range(of: "<?xml") {
            payload = Data(text[range.lowerBound...].utf8)
        }

        guard
            let plist = try PropertyListSerialization.propertyList(from: payload, format: nil) as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]]
        else {
            throw MountError.noMountPointFound
        }

        for entity in entities {
            guard
                let mountPoint = entity["mount-point"] as? String,
                let rawEntry = entity["dev-entry"] as? String
            else { continue }
            let deviceEntry = rawEntry.hasPrefix("/") ? rawEntry : "/dev/" + rawEntry
            let volumeName = (entity["volume-name"] as? String)
                ?? URL(fileURLWithPath: mountPoint).lastPathComponent
            return MountResult(
                mountPoint: URL(fileURLWithPath: mountPoint),
                deviceEntry: deviceEntry,
                volumeName: volumeName
            )
        }
        throw MountError.noMountPointFound
    }
}
