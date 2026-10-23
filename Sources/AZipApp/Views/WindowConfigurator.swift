import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    /// 窗口就绪后的回调，用于应用会话在窗口出现前排队的尺寸。
    var onWindowReady: (@MainActor (NSWindow) -> Void)?
    /// 真实窗口关闭时的回调。SwiftUI 的 `onDisappear` 在启动时会被误触发，不能用于卸载卷。
    var onWindowClose: (@MainActor () -> Void)?

    @MainActor
    final class Coordinator: NSObject {
        weak var window: NSWindow?
        var onClose: (@MainActor () -> Void)?

        /// 窗口通知总在主线程发出，与 MainActor 一致。
        @objc func windowWillClose(_ notification: Notification) {
            onClose?()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window, coordinator: context.coordinator)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window, coordinator: context.coordinator)
        }
    }

    @MainActor
    private func configure(_ window: NSWindow?, coordinator: Coordinator) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // 透明窗口 + 铺满 contentView 的 behindWindow 材质：模糊由窗口服务器采样合成，
        // 背后文字被糊掉，但仍能看到颜色与形状。
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.minSize = NSSize(width: 480, height: 320)

        installVisualEffectView(in: window)

        onWindowReady?(window)

        // 只在首次看到该窗口时注册一次关闭监听。
        guard coordinator.window !== window else { return }
        if let previous = coordinator.window {
            NotificationCenter.default.removeObserver(
                coordinator,
                name: NSWindow.willCloseNotification,
                object: previous
            )
        }
        coordinator.window = window
        coordinator.onClose = onWindowClose
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    /// 把唯一一个 `NSVisualEffectView` 铺在 `contentView` 最底层，随窗口尺寸自适应。
    /// 放在 AppKit 层而不是 SwiftUI 里：SwiftUI 内容会被标题栏安全区裁掉，
    /// 材质无法覆盖标题栏区域，背后应用的文字就会从顶部透出来。
    @MainActor
    private func installVisualEffectView(in window: NSWindow) {
        guard let contentView = window.contentView else { return }

        // 宿主视图不能自己画不透明底色，否则会盖住底层材质。
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
        for subview in contentView.subviews where !(subview is NSVisualEffectView) {
            subview.wantsLayer = true
            subview.layer?.backgroundColor = NSColor.clear.cgColor
        }

        // 幂等：重复进入 `updateNSView` 时复用已安装的材质视图。
        // contentView 是 `NSHostingView`，它不参与 Auto Layout 的子视图布局，
        // 约束会把材质视图留在 0×0（表现为整窗全透明），所以用 frame + autoresizing。
        let effectView: NSVisualEffectView
        if let existing = contentView.subviews.compactMap({ $0 as? NSVisualEffectView }).first {
            effectView = existing
            effectView.frame = contentView.bounds
        } else {
            effectView = NSVisualEffectView(frame: contentView.bounds)
            contentView.addSubview(effectView, positioned: .below, relativeTo: nil)
        }
        effectView.autoresizingMask = [.width, .height]

        effectView.material = .hudWindow
        // `.behindWindow` 采样窗口背后的桌面/其他应用并模糊，文字不可读但颜色可见。
        effectView.blendingMode = .behindWindow
        // `.active` 固定渲染；`followsWindowActiveState` 在应用非前台时会退化。
        effectView.state = .active
        // 材质视图自己裁圆角，透明窗口下才能露出圆角。
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true
    }
}
