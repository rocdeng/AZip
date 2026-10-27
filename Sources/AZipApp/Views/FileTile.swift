import AppKit
import AZipCore
import SwiftUI

struct FileTile: View {
    let entry: VolumeEntry
    var iconSize: CGFloat = 64
    let onOpen: () -> Void

    @State private var isHovering = false

    /// MacOS Alias 文件（DMG 里常见的 Applications 别名）需要解析到目标，
    /// 否则系统会给出普通文档图标，而不是文件夹图标。
    private var iconSourceURL: URL {
        if let values = try? entry.url.resourceValues(forKeys: [.isAliasFileKey]),
           values.isAliasFile == true,
           let resolved = try? URL(resolvingAliasFileAt: entry.url) {
            return resolved
        }
        return entry.url
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
            Image(nsImage: NSWorkspace.shared.icon(forFile: iconSourceURL.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            // 直接对符号链接路径取图标：系统已把「文件夹 + 别名徽章」合成好，
            // 自己解析目标再叠角标反而会丢掉徽章、换成闭合文件夹。
            iconView
                .frame(width: iconSize, height: iconSize)

            Text(entry.name)
                .font(.system(size: 11))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
                .padding(.horizontal, 2)
                .frame(maxWidth: iconSize + 28)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(isHovering ? 0.18 : 0))
        )
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2, perform: onOpen)
        .onDrag {
            NSItemProvider(contentsOf: entry.url) ?? NSItemProvider()
        }
        .help(entry.name)
    }
}
