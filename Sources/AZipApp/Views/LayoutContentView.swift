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
                // 原图不透明铺满：任何透明度都会让底层毛玻璃材质混色，整体发灰发暗，
                // 与系统窗口里看到的 DMG 背景对不上。
                Image(nsImage: image)
                    .frame(width: image.size.width, height: image.size.height, alignment: .topLeading)
            }

            ForEach(positionedEntries) { entry in
                let point = layout.iconPositions[entry.name] ?? .zero
                FileTile(entry: entry, iconSize: layout.iconSize, labelColor: labelColor) {
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

    /// 标签颜色跟随背景亮度：白底用黑字、深色背景用白字。
    /// App 可能运行在深色模式，直接用 `.primary` 会在浅色背景图上变成白底白字。
    private var labelColor: Color {
        Self.labelColor(for: layout)
    }

    @MainActor
    private static var brightnessCache: [String: Double] = [:]

    @MainActor
    private static func labelColor(for layout: DMGWindowLayout) -> Color {
        // 窗口背景色优先：有些 DMG 的背景图是透明 PNG（只有光晕/箭头），
        // 真实底色来自 `.DS_Store` 的背景色，拿透明图算亮度会得出相反结论。
        if let components = layout.backgroundColor,
           let rgba = DMGWindowLayout.normalizedBackgroundColor(components) {
            let brightness = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
            return brightness > 0.55 ? .black : .white
        }
        if let url = layout.backgroundImageURL {
            if let cached = brightnessCache[url.path] {
                return cached > 0.55 ? .black : .white
            }
            if let image = NSImage(contentsOf: url),
               let brightness = averageBrightness(of: image) {
                brightnessCache[url.path] = brightness
                return brightness > 0.55 ? .black : .white
            }
            return .primary
        }
        return .primary
    }

    /// 把背景图缩到 1×1 取平均亮度。
    private static func averageBrightness(of image: NSImage) -> Double? {
        guard let cgImage = image.cgImage(
            forProposedRect: nil, context: nil, hints: nil
        ) else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        let red = Double(pixel[0])
        let green = Double(pixel[1])
        let blue = Double(pixel[2])
        return (0.299 * red + 0.587 * green + 0.114 * blue) / 255
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
