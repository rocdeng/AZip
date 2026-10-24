import AppKit

/// 记住独立对话框最后被拖动到的位置；没有记录或记录已不在任何屏幕上时，
/// 居中显示在父窗口中心。
@MainActor
enum WindowFrameMemory {
    private static let prefix = "windowOrigin."

    static func savedOrigin(for key: String) -> NSPoint? {
        guard let raw = UserDefaults.standard.string(forKey: prefix + key) else {
            return nil
        }
        let parts = raw.split(separator: ",")
        guard parts.count == 2,
              let x = Double(parts[0]),
              let y = Double(parts[1]) else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    static func save(_ window: NSWindow, key: String) {
        let origin = window.frame.origin
        UserDefaults.standard.set(
            "\(origin.x),\(origin.y)",
            forKey: prefix + key
        )
    }

    /// 首次显示放在 `parent` 中心；有记忆且仍可见则恢复记忆位置。
    static func place(_ window: NSWindow, key: String, centeredOn parent: NSWindow?) {
        if let origin = savedOrigin(for: key),
           isOnVisibleScreen(origin: origin, size: window.frame.size) {
            window.setFrameOrigin(origin)
            return
        }

        guard let parent else {
            window.center()
            return
        }
        let target = NSPoint(
            x: parent.frame.midX - window.frame.width / 2,
            y: parent.frame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(target)
    }

    private static func isOnVisibleScreen(origin: NSPoint, size: NSSize) -> Bool {
        let rect = NSRect(origin: origin, size: size)
        return NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }
}
