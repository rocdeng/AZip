import AppKit
import AZipCore
import SwiftUI

struct FileTile: View {
    let entry: VolumeEntry
    var iconSize: CGFloat = 64
    let onOpen: () -> Void

    @State private var isHovering = false

    /// 符号链接取目标图标：DMG 里的 Applications 快捷方式要显示成蓝色文件夹，
    /// 而不是带箭头的链接图钉。
    private var iconURL: URL {
        guard entry.kind == .symbolicLink,
              let destination = try? FileManager.default.destinationOfSymbolicLink(
                  atPath: entry.url.path
              ) else {
            return entry.url
        }
        return URL(fileURLWithPath: destination)
    }

    private var aliasBadge: some View {
        let side = iconSize * 0.34
        return Image(systemName: "arrow.turn.up.right")
            .font(.system(size: side * 0.58, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: side, height: side)
            .background(
                Circle()
                    .fill(Color(nsColor: .secondaryLabelColor).opacity(0.75))
            )
            .overlay(Circle().strokeBorder(.white.opacity(0.6), lineWidth: 0.8))
            .offset(x: -iconSize * 0.02, y: iconSize * 0.02)
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: iconURL.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .overlay(alignment: .bottomLeading) {
                    // Finder 给快捷方式加的下弯小箭头角标，符号链接才有。
                    if entry.kind == .symbolicLink {
                        aliasBadge
                    }
                }

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
