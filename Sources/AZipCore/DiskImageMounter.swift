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
    private static let diskutil = "/usr/sbin/diskutil"

    /// 是否为加密映像（需要密码才能挂载）。
    public static func isEncrypted(_ dmgURL: URL) async -> Bool {
        guard let result = try? await ProcessRunner.run(
            hdiutil, ["isencrypted", dmgURL.path], timeoutSeconds: 20
        ) else {
            return false
        }
        return result.stdout.contains("encrypted: YES")
    }

    public static func attach(_ dmgURL: URL, password: String? = nil) async throws -> MountResult {
        // macOS 26 起 `hdiutil attach` 已弃用，官方替代是 `diskutil image attach`；
        // 后者也支持从 stdin 读取口令，避免弹出系统密码框。
        var arguments = [
            "image", "attach", dmgURL.path, "--plist", "--readOnly", "--nobrowse"
        ]
        if password != nil {
            arguments.append("--stdinpass")
        }
        let result = try await ProcessRunner.run(
            diskutil,
            arguments,
            standardInput: password.map { $0 + "\n" },
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
        guard
            let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let entities = plist["system-entities"] as? [[String: Any]]
        else {
            throw MountError.noMountPointFound
        }

        for entity in entities {
            guard
                let mountPoint = entity["mount-point"] as? String,
                let rawEntry = entity["dev-entry"] as? String
            else { continue }
            // diskutil 返回 "disk8s1"，hdiutil 返回 "/dev/disk8s1"；统一成后者。
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
