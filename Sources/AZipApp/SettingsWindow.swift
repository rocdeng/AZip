import SwiftUI

/// 把 SwiftUI 的 `openSettings` 环境动作暴露给 AppKit 层。
///
/// `Settings` 场景只能通过 SwiftUI 的 `openSettings` 打开；`NSApp.sendAction`
/// 那条旧 selector 路径在当前系统中不可靠。根视图在出现时注册 opener，
/// AppDelegate 直接调用 `present()`。
@MainActor
enum SettingsWindow {
    static var opener: (() -> Void)?

    static func present() {
        opener?()
    }
}
