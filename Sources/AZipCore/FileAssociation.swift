import CoreServices
import Foundation

public enum FileAssociationError: Error, Sendable {
    case setFailed(uti: String, status: OSStatus)
}

public enum FileAssociationService {
    /// 具体 UTI 优先，父类型兜底。Finder 双击 dmg 时两者都会被查询。
    public static let diskImageUTIs = ["com.apple.disk-image-udif", "public.disk-image"]

    public static let systemDiskImageHandler = "com.apple.DiskImageMounter"

    public static func currentHandler(for uti: String) -> String? {
        guard let unmanaged = LSCopyDefaultRoleHandlerForContentType(
            uti as CFString, .all
        ) else {
            return nil
        }
        return unmanaged.takeRetainedValue() as String
    }

    public static func isDefault(bundleID: String) -> Bool {
        diskImageUTIs.contains { currentHandler(for: $0) == bundleID }
    }

    public static func setDefault(bundleID: String) throws {
        for uti in diskImageUTIs {
            let status = LSSetDefaultRoleHandlerForContentType(
                uti as CFString, .all, bundleID as CFString
            )
            if status != noErr {
                throw FileAssociationError.setFailed(uti: uti, status: status)
            }
        }
    }

    public static func restoreSystemDefault() throws {
        try setDefault(bundleID: systemDiskImageHandler)
    }
}
