import CoreServices
import Foundation

public enum FileAssociationError: LocalizedError, Sendable {
    case setFailed(uti: String, status: OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .setFailed(uti, status):
            return String(
                format: NSLocalizedString("无法将 %@ 设为默认打开方式（错误码 %d）", comment: ""),
                uti,
                status
            )
        }
    }
}

/// 一个可供用户选择关联的文件类型。
public struct FileTypeAssociation: Sendable, Identifiable, Hashable {
    /// 主 UTI：决定双击行为，也是状态判定依据。
    public let id: String
    private let labelKey: String
    public var label: String {
        NSLocalizedString(labelKey, comment: "")
    }
    public let fileExtensions: [String]
    /// 恢复时使用的系统默认处理程序。
    public let systemHandler: String

    public init(
        id: String,
        label: String,
        fileExtensions: [String],
        systemHandler: String
    ) {
        self.id = id
        self.labelKey = label
        self.fileExtensions = fileExtensions
        self.systemHandler = systemHandler
    }
}

public enum FileAssociationService {
    /// 具体 UTI 优先，父类型兜底。Finder 双击 dmg 时两者都会被查询。
    public static let diskImageUTIs = ["com.apple.disk-image-udif", "public.disk-image"]

    public static let systemDiskImageHandler = "com.apple.DiskImageMounter"

    /// 设置页展示的可关联格式。压缩类格式的「打开/解压」能力在后续版本提供，
    /// 这里先把关联入口做出来。
    public static let supportedTypes: [FileTypeAssociation] = [
        FileTypeAssociation(
            id: "com.apple.disk-image-udif",
            label: "DMG 磁盘映像",
            fileExtensions: ["dmg"],
            systemHandler: systemDiskImageHandler
        ),
        FileTypeAssociation(
            id: "public.zip-archive",
            label: "ZIP 压缩包",
            fileExtensions: ["zip"],
            systemHandler: "com.apple.archiveutility"
        ),
        FileTypeAssociation(
            id: "com.rarlab.rar-archive",
            label: "RAR 压缩包",
            fileExtensions: ["rar"],
            systemHandler: "com.apple.archiveutility"
        ),
        FileTypeAssociation(
            id: "org.7-zip.7-zip-archive",
            label: "7-Zip 压缩包",
            fileExtensions: ["7z"],
            systemHandler: "com.apple.archiveutility"
        ),
        FileTypeAssociation(
            id: "public.tar-archive",
            label: "TAR 归档",
            fileExtensions: ["tar"],
            systemHandler: "com.apple.archiveutility"
        ),
        FileTypeAssociation(
            id: "org.gnu.gnu-zip-tar-archive",
            label: "TGZ 归档",
            fileExtensions: ["tgz"],
            systemHandler: "com.apple.archiveutility"
        ),
        FileTypeAssociation(
            id: "org.gnu.gnu-zip-archive",
            label: "GZIP 压缩",
            fileExtensions: ["gz"],
            systemHandler: "com.apple.archiveutility"
        ),
        FileTypeAssociation(
            id: "public.bzip2-archive",
            label: "BZIP2 压缩",
            fileExtensions: ["bz2"],
            systemHandler: "com.apple.archiveutility"
        ),
        FileTypeAssociation(
            id: "org.tukaani.xz-archive",
            label: "XZ 压缩",
            fileExtensions: ["xz"],
            systemHandler: "com.apple.archiveutility"
        )
    ]

    public static func isDefault(bundleID: String, for type: FileTypeAssociation) -> Bool {
        currentHandler(for: type.id) == bundleID
    }

    public static func setDefault(bundleID: String, for type: FileTypeAssociation) throws {
        let status = LSSetDefaultRoleHandlerForContentType(
            type.id as CFString, .all, bundleID as CFString
        )
        if status != noErr {
            throw FileAssociationError.setFailed(uti: type.id, status: status)
        }
    }

    public static func restoreSystemDefault(for type: FileTypeAssociation) throws {
        let status = LSSetDefaultRoleHandlerForContentType(
            type.id as CFString, .all, type.systemHandler as CFString
        )
        if status != noErr {
            throw FileAssociationError.setFailed(uti: type.id, status: status)
        }
    }

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
