import CoreGraphics
import Foundation

public struct DMGWindowLayout: Sendable {
    public static let defaultSize = CGSize(width: 640, height: 400)
    public static let minimumSize = CGSize(width: 480, height: 320)
    public static let maximumSize = CGSize(width: 1600, height: 1200)
    public static let defaultIconSize: CGFloat = 64
    public static let minimumIconSize: CGFloat = 48
    public static let maximumIconSize: CGFloat = 128

    public let contentSize: CGSize
    public let backgroundImageURL: URL?
    public let backgroundColor: [CGFloat]?
    public let iconPositions: [String: CGPoint]
    public let iconSize: CGFloat

    public static func make(mountPoint: URL, document: DSStoreDocument) -> DMGWindowLayout? {
        let background = resolveBackgroundImage(mountPoint: mountPoint, document: document)
        guard background != nil || !document.iconPositions.isEmpty else { return nil }

        let rawSize = document.windowFrame?.size ?? defaultSize
        let baseSize = rawSize.width.isFinite && rawSize.height.isFinite ? rawSize : defaultSize
        let contentSize = CGSize(
            width: min(max(baseSize.width, minimumSize.width), maximumSize.width),
            height: min(max(baseSize.height, minimumSize.height), maximumSize.height)
        )
        let rawIconSize = document.iconSize ?? defaultIconSize
        let iconSize = min(
            max(rawIconSize.isFinite ? rawIconSize : defaultIconSize, minimumIconSize),
            maximumIconSize
        )

        return DMGWindowLayout(
            contentSize: contentSize,
            backgroundImageURL: background,
            backgroundColor: document.backgroundColor,
            iconPositions: document.iconPositions,
            iconSize: iconSize
        )
    }

    // MARK: - Background

    public static func resolveBackgroundImage(
        mountPoint: URL,
        document: DSStoreDocument
    ) -> URL? {
        if let alias = document.backgroundAlias,
           let fileName = resolveAliasFileName(alias),
           let url = backgroundImage(mountPoint: mountPoint, fileName: fileName) {
            return url
        }

        guard let backgroundDirectory = backgroundDirectory(for: mountPoint),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: backgroundDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ) else {
            return nil
        }
        return entries
            .filter { hasImageExtension($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first { isValidBackgroundFile($0, mountPoint: mountPoint) }
    }

    /// 只接受带图片扩展名的纯文件名，拒绝任何路径分隔或上跳片段。
    public static func backgroundImage(mountPoint: URL, fileName: String) -> URL? {
        guard !fileName.isEmpty,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              fileName != ".",
              fileName != "..",
              !fileName.hasPrefix(".."),
              hasImageExtension(fileName) else {
            return nil
        }

        var candidates: [URL] = []
        if let backgroundDirectory = backgroundDirectory(for: mountPoint) {
            candidates.append(backgroundDirectory.appendingPathComponent(fileName))
        }
        candidates.append(mountPoint.appendingPathComponent(fileName))
        return candidates.first { isValidBackgroundFile($0, mountPoint: mountPoint) }
    }

    // MARK: - File safety

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "gif"]

    private static func hasImageExtension(_ fileName: String) -> Bool {
        imageExtensions.contains((fileName as NSString).pathExtension.lowercased())
    }

    /// `.background` 必须是挂载点内的真实目录，不能是 symlink。
    private static func backgroundDirectory(for mountPoint: URL) -> URL? {
        let directory = mountPoint.appendingPathComponent(".background")
        guard let values = try? directory.resourceValues(
            forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
        ),
            values.isDirectory == true,
            values.isSymbolicLink != true else {
            return nil
        }
        return directory
    }

    /// 候选文件必须是挂载点内的常规文件，且不是 symlink 或逃逸到挂载点之外。
    private static func isValidBackgroundFile(_ candidate: URL, mountPoint: URL) -> Bool {
        guard let values = try? candidate.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ),
            values.isRegularFile == true,
            values.isSymbolicLink != true else {
            return false
        }

        // 两侧都解析 symlink 后再比较：macOS 上 /var 指向 /private/var，
        // 只解析一侧会产生假阴性。
        let resolvedMountPath = mountPoint.resolvingSymlinksInPath().path
        let resolvedCandidatePath = candidate.resolvingSymlinksInPath().path
        return resolvedCandidatePath == resolvedMountPath
            || resolvedCandidatePath.hasPrefix(resolvedMountPath + "/")
    }

    /// 把 `.DS_Store` 里的 alias 数据解析成文件名（仅取 `lastPathComponent`）。
    public static func resolveAliasFileName(_ alias: Data) -> String? {
        guard let bookmark = CFURLCreateBookmarkDataFromAliasRecord(
            nil, alias as CFData
        )?.takeRetainedValue() else {
            return nil
        }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark as Data,
            options: [.withoutUI, .withoutMounting],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else {
            return nil
        }
        let name = url.lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            return nil
        }
        return name
    }
}
