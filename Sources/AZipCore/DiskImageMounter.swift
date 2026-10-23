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

    public static func attach(_ dmgURL: URL) async throws -> MountResult {
        let result = try await ProcessRunner.run(
            hdiutil,
            ["attach", dmgURL.path, "-plist", "-nobrowse", "-noautoopen", "-readonly"],
            timeoutSeconds: 120
        )
        guard result.status == 0 else {
            throw MountError.toolFailed(code: result.status, message: result.stderr)
        }
        return try parseAttachOutput(Data(result.stdout.utf8))
    }

    public static func detach(_ result: MountResult) async throws {
        let plain = try await ProcessRunner.run(
            hdiutil, ["detach", result.deviceEntry], timeoutSeconds: 30
        )
        if plain.status == 0 { return }

        let forced = try await ProcessRunner.run(
            hdiutil, ["detach", result.deviceEntry, "-force"], timeoutSeconds: 30
        )
        if forced.status != 0 {
            throw MountError.toolFailed(code: forced.status, message: forced.stderr)
        }
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
                let deviceEntry = entity["dev-entry"] as? String
            else { continue }
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
