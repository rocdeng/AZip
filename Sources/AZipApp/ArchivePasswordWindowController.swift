import AppKit
import QuartzCore
import SwiftUI

/// 加密压缩包的密码输入浮窗：独立小窗、毛玻璃，和解压浮窗一样不占主窗口。
@MainActor
final class ArchivePasswordWindowController {
    static let shared = ArchivePasswordWindowController()

    private var window: NSWindow?
    private let size = NSSize(width: 280, height: 210)

    func show() {
        guard let request = ArchiveSession.shared.passwordRequest else { return }

        let view = PasswordPromptView(
            fileName: request.url.lastPathComponent,
            message: request.message,
            title: NSLocalizedString("此压缩包已加密", comment: ""),
            submitTitle: NSLocalizedString("解压", comment: ""),
            onSubmit: { password in
                // 是否收起窗口由 ArchiveSession 决定：空密码时窗口留在原处直接提示错误。
                ArchiveSession.shared.submitPassword(password)
            },
            onCancel: {
                ArchivePasswordWindowController.shared.close()
                ArchiveSession.shared.cancelPasswordPrompt()
            }
        )

        // 密码窗口独占前台：主窗口（此时是空白页）先让位，
        // 与解压浮窗的行为保持一致。
        for main in NSApp.windows
        where main.identifier?.rawValue == "AZipMainWindow" {
            main.orderOut(nil)
        }

        let window = self.window ?? makeWindow()
        self.window = window

        // 每次重建内容：密码错误重试时要用新的 message，
        // 复用旧的 hosting 视图会继续显示上一轮内容。
        let container = makeContainer()
        let hosting = NSHostingView(rootView: view)
        hosting.frame = container.bounds
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        window.contentView = container

        window.setContentSize(size)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // 让 SwiftUI 宿主先拿到焦点，输入框的 @FocusState 才会生效。
        DispatchQueue.main.async {
            window.makeFirstResponder(hosting)
            Self.focusPasswordField(in: hosting, window: window)
            // 带错误提示重新弹出，说明上一次密码不对：左右摇一下。
            if request.message != nil {
                Self.shake(window)
            }
        }
    }

    /// 把键盘焦点直接放进密码输入框。
    /// 只靠 SwiftUI 的 @FocusState 不可靠：窗口重新弹出时内容是新建的，
    /// 焦点会停在宿主视图上，用户还得先点一下输入框。
    /// 新建的 SwiftUI 内容可能还没生成底层输入框，先强制布局，找不到再隔一拍重试几次。
    private static func focusPasswordField(
        in hosting: NSView,
        window: NSWindow,
        attemptsLeft: Int = 10
    ) {
        hosting.layoutSubtreeIfNeeded()
        if let field = firstTextField(in: hosting) {
            window.makeFirstResponder(field)
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak hosting, weak window] in
            guard let hosting, let window else { return }
            focusPasswordField(in: hosting, window: window, attemptsLeft: attemptsLeft - 1)
        }
    }

    private static func firstTextField(in view: NSView) -> NSTextField? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.isEditable { return field }
            if let found = firstTextField(in: subview) { return found }
        }
        return nil
    }

    /// 仿系统登录框的「密码错误」效果：窗口左右快速摆动几次，幅度逐渐减小，回到原位。
    /// 开启「减弱动态效果」时不摇，只保留红色错误提示。
    private static func shake(_ window: NSWindow) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }

        let origin = window.frame.origin
        let offsets: [CGFloat] = [0, -10, 10, -8, 8, -5, 5, -2, 2, 0]
        let path = CGMutablePath()
        path.move(to: origin)
        for offset in offsets.dropFirst() {
            path.addLine(to: CGPoint(x: origin.x + offset, y: origin.y))
        }

        let animation = CAKeyframeAnimation()
        animation.path = path
        animation.duration = 0.4
        animation.calculationMode = .linear

        // 给窗口的 frameOrigin 挂上关键帧动画，再通过 animator 触发；
        // 目标位置就是原位，动画结束后窗口停在原处。
        window.animations = ["frameOrigin": animation]
        window.animator().setFrameOrigin(origin)
    }

    func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        // 无边框窗口默认不能成为 key window，键盘输入会完全失效，
        // 必须用子类把 canBecomeKey 打开。
        let window = PasswordKeyWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        return window
    }

    private func makeContainer() -> NSView {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = 14
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true

        let effect = NSVisualEffectView(frame: container.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.alphaValue = 0.99
        container.addSubview(effect)
        return container
    }
}


/// 无边框但仍能接收键盘输入的窗口。
private final class PasswordKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
