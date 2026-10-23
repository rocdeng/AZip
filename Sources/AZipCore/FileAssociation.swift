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
        // 只有具体 UTI 能代表 .dmg 的双击行为；父类型可能仍指向本应用却无实际效果。
        guard let primaryUTI = diskImageUTIs.first else { return false }
        return currentHandler(for: primaryUTI) == bundleID
    }

    public static func setDefault(bundleID: String) throws {
        guard let primaryUTI = diskImageUTIs.first else { return }
        let status = LSSetDefaultRoleHandlerForContentType(
            primaryUTI as CFString, .all, bundleID as CFString
        )
        if status != noErr {
            throw FileAssociationError.setFailed(uti: primaryUTI, status: status)
        }
        // 父类型仅作兜底：LaunchServices 可能不支持该 UTI 或返回 noErr 却不生效，
        // 因此其失败不影响整体结果，具体 UTI 才是判定依据。
        for uti in diskImageUTIs.dropFirst() {
            _ = LSSetDefaultRoleHandlerForContentType(
                uti as CFString, .all, bundleID as CFString
            )
        }
    }

    public static func restoreSystemDefault() throws {
        // LSCopyAllRoleHandlersForContentType("public.disk-image") 并不列出
        // DiskImageMounter，因此父类型的恢复不可靠；只要求具体 UTI 恢复成功。
        try setDefault(bundleID: systemDiskImageHandler)
    }
}
