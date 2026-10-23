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
            }

            ForEach(positionedEntries) { entry in
                let point = layout.iconPositions[entry.name] ?? .zero
                FileTile(entry: entry, iconSize: layout.iconSize) {
                    onOpen(entry)
                }
                .position(x: point.x, y: point.y)
            }

            if !unpositionedEntries.isEmpty {
                VStack {
                    Spacer()
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(unpositionedEntries) { entry in
                                FileTile(entry: entry, iconSize: layout.iconSize) {
                                    onOpen(entry)
                                }
                            }
                        }
                        .padding(12)
                    }
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    @ViewBuilder
    private var backgroundColor: some View {
        if let components = layout.backgroundColor, components.count >= 4 {
            Color(
                .sRGB,
                red: components[0],
                green: components[1],
                blue: components[2],
                opacity: components[3]
            )
        } else {
            Color.clear
        }
    }
}
