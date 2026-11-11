import AppKit
import AZipCore
import SwiftUI

struct FileTile: View {
    let entry: VolumeEntry
    var iconSize: CGFloat = 64
    /// DMG 背景图有深有浅，标签颜色必须由背景亮度决定，
    /// 不能跟随系统外观（否则白底图上会出现白字）。
    var labelColor: Color = .primary
    let onOpen: () -> Void

    @State private var isHovering = false

    /// 系统图标。
    ///
    /// - 符号链接（`Applications -> /Applications`）：直接用链接路径，
    ///   系统才会合成「文件夹 + 左下角箭头」；解析到目标只会得到普通文件夹。
    /// - MacOS Alias 文件（少数 DMG 用这种）：原路径只给文档图标，
    ///   解析目标又没有箭头——借一个临时符号链接拿到带箭头的版本。
    private var systemIcon: NSImage {
        guard let values = try? entry.url.resourceValues(
            forKeys: [.isAliasFileKey, .isSymbolicLinkKey]
        ) else {
            return NSWorkspace.shared.icon(forFile: entry.url.path)
        }
        if values.isSymbolicLink == true {
            return NSWorkspace.shared.icon(forFile: entry.url.path)
        }
        if values.isAliasFile == true,
           let resolved = try? URL(resolvingAliasFileAt: entry.url) {
            return AliasIconCache.icon(for: entry.url, target: resolved)
        }
        return NSWorkspace.shared.icon(forFile: entry.url.path)
    }

    /// 归档类文件用自绘图标，其余交给系统。
    @ViewBuilder
    private var iconView: some View {
        if let style = FileTypeIconStyle.style(
            forExtension: entry.url.pathExtension
        ) {
            // 优先用设计稿导出的 PNG；缺失时回退到矢量绘制。
            if let image = NSImage(named: style.key) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                FileTypeIcon(style: style)
            }
        } else {
            Image(nsImage: systemIcon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }

    /// Finder 的图标视图里标签紧贴图标下方；DMG 背景图的白条就是按这个位置画的。
    private static let labelSpacing: CGFloat = 10

    /// 与 Finder 一致：`.app` 等扩展名默认隐藏，显示 `Blender` 而不是 `Blender.app`。
    private var displayName: String {
        FileManager.default.displayName(atPath: entry.url.path)
    }

    var body: some View {
        // 图标单独占满 frame，文字用 overlay 向下溢出：
        // 这样 `.position()` 对齐的是「图标中心」而不是「图标+文字」整体的中心，
        // 图标才不会比系统窗口里的位置高出一截。
        iconView
            .frame(width: iconSize, height: iconSize)
            .overlay(alignment: .top) {
                Text(displayName)
                    .font(.system(size: 11))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(labelColor)
                    // 必须给固定宽度：overlay 的提议尺寸只有图标那么大（64pt），
                    // maxWidth 不会撑开容器，"Applications" 会被折成 "Application/s"。
                    .frame(width: iconSize + 44)
                    .offset(y: iconSize + Self.labelSpacing)
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.accentColor.opacity(isHovering ? 0.18 : 0))
            )
            .onHover { isHovering = $0 }
            .onTapGesture(count: 2, perform: onOpen)
            .onDrag {
                // 拖放安装不走「快速安装」，这里登记一次，用于装完后按开关清理 dmg。
                DMGSessionModel.shared.noteDragInstall(of: entry)
                return NSItemProvider(contentsOf: entry.url) ?? NSItemProvider()
            }
            .help(entry.name)
    }
}

/// MacOS Alias 文件取带箭头图标用的临时符号链接。
///
/// `NSWorkspace.icon(forFile:)` 对视作别名的普通文件只会给文档图标，
/// 解析到目标又拿不到箭头徽章；指向目标的符号链接才两者兼得。
/// 按别名路径缓存，避免列表重绘时反复建/删链接。
@MainActor
private enum AliasIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for aliasURL: URL, target: URL) -> NSImage {
        if let cached = cache[aliasURL.path] { return cached }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("azip-alias-links", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let link = directory.appendingPathComponent(UUID().uuidString)

        let image: NSImage
        if (try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)) != nil {
            image = NSWorkspace.shared.icon(forFile: link.path)
            try? FileManager.default.removeItem(at: link)
        } else {
            image = NSWorkspace.shared.icon(forFile: target.path)
        }
        cache[aliasURL.path] = image
        return image
    }
}
