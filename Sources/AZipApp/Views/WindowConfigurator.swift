import AppKit
import SwiftUI

struct WindowConfigurator: NSViewRepresentable {
    /// 窗口就绪后的回调，用于应用会话在窗口出现前排队的尺寸。
    var onWindowReady: (@MainActor (NSWindow) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    @MainActor
    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isMovableByWindowBackground = true
        window.hasShadow = true
        window.minSize = NSSize(width: 480, height: 320)
        onWindowReady?(window)
    }
}
