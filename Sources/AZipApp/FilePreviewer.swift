import AppKit
import Foundation
import SwiftUI
import AZipCore

/// 悬停预览内容。
enum PreviewContent {
    case image(NSImage)
    case text(String)
    case unavailable(String)
}

/// 鼠标悬停在文件图标上时弹出的悬浮预览窗。
///
/// 内容来自浏览模式的预提取目录（`ArchiveBrowseSession.dragURL`）；
/// 若文件还没解压出来，会先解压再展示。
@MainActor
final class FilePreviewer: ObservableObject {
    static let shared = FilePreviewer()

    private var window: NSWindow?
    private var showTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var currentPath: String?

    private let showDelay: Duration = .milliseconds(420)
    private let hideDelay: Duration = .milliseconds(180)

    // MARK: - Hover

    func beginHover(entry: ArchiveEntry, session: ArchiveBrowseSession) {
        guard !entry.isDirectory else { return }
        hideTask?.cancel()
        showTask?.cancel()

        showTask = Task { [weak self] in
            try? await Task.sleep(for: self?.showDelay ?? .milliseconds(420))
            guard let self, !Task.isCancelled else { return }
            await self.present(entry: entry, session: session)
        }
    }

    func endHover() {
        showTask?.cancel()
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: self?.hideDelay ?? .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            self.hide()
        }
    }

    // MARK: - Presentation

    private func present(entry: ArchiveEntry, session: ArchiveBrowseSession) async {
        // 已解压的文件直接用；没有就让会话解压一份。
        let fileURL: URL?
        if let existing = session.dragURL(for: entry) {
            fileURL = existing
        } else {
            fileURL = await session.prepareForDrag(entry)
        }
        guard let fileURL else {
            show(content: .unavailable(NSLocalizedString("无法预览此文件", comment: "")), for: entry)
            return
        }
        guard !Task.isCancelled else { return }

        let content = Self.loadContent(for: fileURL, name: entry.name)
        show(content: content, for: entry)
    }

    private func show(content: PreviewContent, for entry: ArchiveEntry) {
        // 同一个文件重复悬停时避免闪烁。
        if currentPath == entry.path, window != nil { return }

        let size = Self.preferredSize(for: content)
        let root = PreviewContentView(content: content)
            .frame(width: size.width, height: size.height)

        let window = existingOrNewWindow(size: size, rootView: root)
        window.setContentSize(size)
        window.contentView = NSHostingView(rootView: root)

        var origin = Self.origin(for: size)
        origin = Self.clampToScreen(origin: origin, size: size)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()

        self.window = window
        currentPath = entry.path
    }

    func hide() {
        showTask?.cancel()
        window?.orderOut(nil)
        window = nil
        currentPath = nil
    }

    private func existingOrNewWindow(size: NSSize, rootView: some View) -> NSWindow {
        if let window { return window }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        return window
    }

    // MARK: - Content

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "heic", "webp", "icns"
    ]

    static func loadContent(for url: URL, name: String) -> PreviewContent {
        let ext = (name as NSString).pathExtension.lowercased()

        if imageExtensions.contains(ext), let image = NSImage(contentsOf: url) {
            return .image(image)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return .unavailable(NSLocalizedString("无法预览此文件", comment: ""))
        }
        defer { try? handle.close() }
        let sample = (try? handle.read(upToCount: 8192)) ?? Data()

        if let text = decodeText(sample) {
            return .text(text)
        }
        let size = ByteCountFormatter.string(
            fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0),
            countStyle: .file
        )
        return .unavailable(
            String(
                format: NSLocalizedString("%@ · 无法预览此类型", comment: ""),
                size
            )
        )
    }

    private static func decodeText(_ data: Data) -> String? {
        guard !data.isEmpty, !data.contains(0) else { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }

        let gbEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        return String(data: data, encoding: gbEncoding)
    }

    private static func preferredSize(for content: PreviewContent) -> NSSize {
        switch content {
        case let .image(image):
            let maxSize = NSSize(width: 360, height: 260)
            let width = max(image.size.width, 1)
            let height = max(image.size.height, 1)
            let scale = min(1, min(maxSize.width / width, maxSize.height / height))
            return NSSize(
                width: max(120, width * scale),
                height: max(80, height * scale)
            )
        case .text:
            return NSSize(width: 360, height: 200)
        case .unavailable:
            return NSSize(width: 220, height: 60)
        }
    }

    private static func origin(for size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        return NSPoint(x: mouse.x + 18, y: mouse.y - size.height - 12)
    }

    private static func clampToScreen(origin: NSPoint, size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: {
            $0.frame.contains(NSEvent.mouseLocation)
        }) ?? NSScreen.main else {
            return origin
        }
        let visible = screen.visibleFrame
        var x = origin.x
        var y = origin.y
        if x + size.width > visible.maxX { x = visible.maxX - size.width - 8 }
        if x < visible.minX { x = visible.minX + 8 }
        if y < visible.minY { y = visible.minY + 8 }
        if y + size.height > visible.maxY { y = visible.maxY - size.height - 8 }
        return NSPoint(x: x, y: y)
    }
}

/// 悬浮预览内容视图。
struct PreviewContentView: View {
    let content: PreviewContent

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)

            switch content {
            case let .image(image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(6)
            case let .text(text):
                ScrollView {
                    Text(text)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
            case let .unavailable(message):
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(14)
            }
        }
    }
}
