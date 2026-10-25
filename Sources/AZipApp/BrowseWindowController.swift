import AppKit
import SwiftUI

/// 浏览模式专用窗口。
///
/// SwiftUI 的 `WindowGroup` 在 Finder 服务启动时不会创建窗口（实测 windows=0），
/// 因此浏览界面自己持有一个 NSWindow，内容仍复用 `RootWindow`（含毛玻璃配置）。
@MainActor
final class BrowseWindowController {
    static let shared = BrowseWindowController()

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: RootWindow(model: DMGSessionModel.shared)
        )
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                BrowseWindowController.shared.handleClose()
            }
        }

        self.window = window
    }

    private func handleClose() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        window = nil
        ArchiveBrowseSession.shared.close()
        // 浏览窗口关闭即结束本次会话。
        exit(0)
    }
}
