import AppKit
import SwiftUI

/// 解压进度专用浮窗：独立于主窗口，无标题栏、全毛玻璃。
@MainActor
final class ExtractionWindowController {
    static let shared = ExtractionWindowController()

    private var panel: NSWindow?
    private var moveObserver: NSObjectProtocol?
    private static let frameKey = "extractionPanel"

    private let panelSize = NSSize(width: 380, height: 84)

    func show(over windowToHide: NSWindow? = nil) {
        windowToHide?.orderOut(nil)

        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))
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

        let host = NSHostingView(rootView: ExtractionPanel())
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(host)

        panel.contentView = container
        WindowFrameMemory.place(panel, key: Self.frameKey, centeredOn: windowToHide)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // 拖动后记住位置，下次直接沿用。
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel,
            queue: .main
        ) { [weak panel] _ in
            guard let panel else { return }
            MainActor.assumeIsolated {
                WindowFrameMemory.save(panel, key: Self.frameKey)
            }
        }

        self.panel = panel
    }

    func close() {
        if let moveObserver {
            NotificationCenter.default.removeObserver(moveObserver)
            self.moveObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
    }
}

/// 浮窗内容：跟随 `ArchiveSession` 的状态刷新。
struct ExtractionPanel: View {
    @ObservedObject private var panel = TaskPanelModel.shared
    @ObservedObject private var model = DMGSessionModel.shared

    var body: some View {
        Group {
            if let state = panel.state {
                TaskPanelView(
                    state: state,
                    onCancel: {
                        switch state.kind {
                        case .extracting:
                            ArchiveSession.shared.cancel()
                        case .installing:
                            DMGSessionModel.shared.cancelInstall()
                        }
                    }
                )
            } else {
                Color.clear
            }
        }
        .id(model.language)
        .environment(\.locale, model.language.locale)
        .frame(width: 380, height: 84)
    }
}
