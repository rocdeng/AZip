import AppKit
import AZipCore
import SwiftUI

struct FileTile: View {
    let entry: VolumeEntry
    var iconSize: CGFloat = 64
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
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
