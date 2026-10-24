import AppKit
import Foundation

/// 通过私有的 `CGSSetWindowBackgroundBlurRadius` 给窗口加系统级背景模糊。
///
/// Dock/菜单栏用的就是这套合成。仅本地自用，不用于分发版本。
/// 全部通过 `dlsym` 动态查找，符号缺失时静默失效，不会崩溃。
@MainActor
final class PrivateWindowBlur {
    static let shared = PrivateWindowBlur()

    private typealias ConnectionFn = @convention(c) () -> UInt32
    private typealias SetBlurFn = @convention(c) (UInt32, Int, Int32) -> Int32

    private let connection: ConnectionFn?
    private let setBlurRadius: SetBlurFn?

    private init() {
        let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
            RTLD_NOW
        )
        guard let handle else {
            connection = nil
            setBlurRadius = nil
            return
        }
        connection = dlsym(handle, "CGSDefaultConnection").map {
            unsafeBitCast($0, to: ConnectionFn.self)
        }
        setBlurRadius = dlsym(handle, "CGSSetWindowBackgroundBlurRadius").map {
            unsafeBitCast($0, to: SetBlurFn.self)
        }
    }

    var isAvailable: Bool {
        connection != nil && setBlurRadius != nil
    }

    @discardableResult
    func apply(to window: NSWindow, radius: Int32) -> Bool {
        guard let connection, let setBlurRadius, window.windowNumber > 0 else {
            return false
        }
        let result = setBlurRadius(connection(), window.windowNumber, radius)
        return result == 0
    }
}
