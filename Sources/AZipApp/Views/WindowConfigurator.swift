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
        // 窗口必须实心：否则毛玻璃材质会把背后应用的文字透出来。
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.minSize = NSSize(width: 480, height: 320)
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
}
