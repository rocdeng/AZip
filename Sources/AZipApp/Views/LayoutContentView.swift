import AppKit
import AZipCore
import SwiftUI

struct LayoutContentView: View {
    let layout: DMGWindowLayout
    let entries: [VolumeEntry]
    let onOpen: (VolumeEntry) -> Void

    private var positionedEntries: [VolumeEntry] {
        entries.filter { layout.iconPositions[$0.name] != nil }
    }

    private var unpositionedEntries: [VolumeEntry] {
        entries.filter { layout.iconPositions[$0.name] == nil }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            backgroundColor

            if let url = layout.backgroundImageURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .frame(width: image.size.width, height: image.size.height, alignment: .topLeading)
                    // 背景图轻微透明，让窗口底层的毛玻璃材质透上来。
                    .opacity(0.85)
            }

            ForEach(positionedEntries) { entry in
                let point = layout.iconPositions[entry.name] ?? .zero
                FileTile(entry: entry, iconSize: layout.iconSize) {
                    onOpen(entry)
                }
                .position(x: point.x, y: point.y)
            }

            if !unpositionedEntries.isEmpty {
                // 没有坐标数据的 DMG（旧式 .ICVO 记录）：居中排成网格，
                // 而不是挤在底部横条里。
                VStack {
                    Spacer()
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 96), spacing: 20)],
                        spacing: 16
                    ) {
                        ForEach(unpositionedEntries) { entry in
                            FileTile(entry: entry, iconSize: layout.iconSize) {
                                onOpen(entry)
                            }
                        }
                    }
                    .frame(maxWidth: min(CGFloat(unpositionedEntries.count) * 116, 520))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var backgroundColor: some View {
        if let components = layout.backgroundColor,
           let rgba = DMGWindowLayout.normalizedBackgroundColor(components) {
            Color(
                .sRGB,
                red: rgba[0],
                green: rgba[1],
                blue: rgba[2],
                opacity: rgba[3]
            )
        } else {
            Color.clear
        }
    }
}
