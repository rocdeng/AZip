import CoreGraphics
import ImageIO
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

        let rawSize = document.windowFrame?.size
            ?? backgroundImagePointSize(background)
            ?? defaultSize
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

    /// 有些 DMG（dmgcanvas 生成）不写窗口尺寸，但背景图就是设计尺寸。
    /// 背景图常为 2x，按最长边是否超过 1200 判断缩放。
    private static func backgroundImagePointSize(_ url: URL?) -> CGSize? {
        guard let url,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else {
            return nil
        }
        let scale: Double = max(width, height) > 1200 ? 2 : 1
        return CGSize(width: width / scale, height: height / scale)
    }

    // MARK: - Background

    /// 把 `.DS_Store` 的背景色分量归一化为 RGBA。
    ///
    /// 真实文件给出 3 个 RGB 分量；这里补上不透明 alpha 后交给渲染层。
    /// 6 个分量是旧版解析器把 RGBA 拆成两半的遗留形态，沿用前三个分量并视为不透明。
    public static func normalizedBackgroundColor(_ components: [CGFloat]) -> [CGFloat]? {
        switch components.count {
        case 3:
            return [components[0], components[1], components[2], 1]
        case 4:
            return components
        case 6:
            return [components[0], components[1], components[2], 1]
        default:
            return nil
        }
    }

    public static func resolveBackgroundImage(
        mountPoint: URL,
        document: DSStoreDocument
    ) -> URL? {
        if let alias = document.backgroundAlias,
           let fileName = resolveAliasFileName(alias),
           let url = backgroundImage(mountPoint: mountPoint, fileName: fileName) {
            return url
        }

        // 后备 1：`.background/` 目录里的图片。
        if let backgroundDirectory = backgroundDirectory(for: mountPoint),
           let entries = try? FileManager.default.contentsOfDirectory(
               at: backgroundDirectory,
               includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
           ) {
            let candidates = entries
                .filter { hasImageExtension($0.lastPathComponent) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let found = candidates.first(where: {
                isValidBackgroundFile($0, mountPoint: mountPoint)
            }) {
                return found
            }
        }

        // 后备 2：背景图直接放在根目录的 DMG（如 `.background.tiff`，WorkBuddy 就是这种）。
        if let rootEntries = try? FileManager.default.contentsOfDirectory(
            at: mountPoint,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]
        ) {
            let candidates = rootEntries
                .filter {
                    $0.lastPathComponent.lowercased().hasPrefix(".background")
                        && hasImageExtension($0.lastPathComponent)
                }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let found = candidates.first(where: {
                isValidBackgroundFile($0, mountPoint: mountPoint)
            }) {
                return found
            }
        }

        return nil
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
