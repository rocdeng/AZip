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
        let contentSize = CGSize(
            width: min(max(rawSize.width, minimumSize.width), maximumSize.width),
            height: min(max(rawSize.height, minimumSize.height), maximumSize.height)
        )
        let iconSize = min(
            max(document.iconSize ?? defaultIconSize, minimumIconSize),
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

        let backgroundDirectory = mountPoint.appendingPathComponent(".background")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: backgroundDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "gif"]
        return entries
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .first
    }

    /// 只接受纯文件名，拒绝任何路径分隔或上跳片段。
    public static func backgroundImage(mountPoint: URL, fileName: String) -> URL? {
        guard !fileName.isEmpty,
              !fileName.contains("/"),
              !fileName.contains("\\"),
              fileName != ".",
              fileName != "..",
              !fileName.hasPrefix("..") else {
            return nil
        }

        let candidates = [
            mountPoint.appendingPathComponent(".background").appendingPathComponent(fileName),
            mountPoint.appendingPathComponent(fileName)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
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
            options: [],
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
