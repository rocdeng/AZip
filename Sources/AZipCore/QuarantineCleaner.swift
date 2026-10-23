import Darwin
import Foundation

public struct QuarantineResult: Sendable, Equatable {
    public let removed: Int
    public let failed: [URL]

    public init(removed: Int, failed: [URL]) {
        self.removed = removed
        self.failed = failed
    }
}

public enum QuarantineCleaner {
    public static let attributeName = "com.apple.quarantine"

    /// 递归移除隔离属性。
    ///
    /// 必须进入 `.app` 包内部，因此枚举时同时关闭隐藏文件跳过与包跳过。
    /// 不跟随符号链接：只处理链接自身的属性，避免影响链接目标。
    public static func remove(at url: URL) -> QuarantineResult {
        var removed = 0
        var failed: [URL] = []

        for target in allURLs(in: url) {
            let outcome = removeAttribute(at: target)
            switch outcome {
            case .removed:
                removed += 1
            case .absent:
                break
            case .failed:
                failed.append(target)
            }
        }
        return QuarantineResult(removed: removed, failed: failed)
    }

    public static func hasQuarantine(at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return getxattr(path, attributeName, nil, 0, 0, XATTR_NOFOLLOW) > 0
        }
    }

    // MARK: - Private

    private enum Outcome {
        case removed
        case absent
        case failed
    }

    private static func allURLs(in root: URL) -> [URL] {
        var urls = [root]
        let keys: [URLResourceKey] = [.isDirectoryKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return urls
        }
        for case let url as URL in enumerator {
            urls.append(url)
        }
        return urls
    }

    private static func removeAttribute(at url: URL) -> Outcome {
        url.withUnsafeFileSystemRepresentation { path -> Outcome in
            guard let path else { return .failed }
            if removexattr(path, attributeName, XATTR_NOFOLLOW) == 0 {
                return .removed
            }
            return errno == ENOATTR ? .absent : .failed
        }
    }
}
