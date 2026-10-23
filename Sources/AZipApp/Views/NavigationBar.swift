import SwiftUI

struct NavigationBar: View {
    let title: String
    let canGoUp: Bool
    let onBackToRoot: () -> Void
    let onUp: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBackToRoot) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .disabled(!canGoUp)
            .keyboardShortcut("[", modifiers: .command)
            .help("返回根目录 ⌘[")

            Button(action: onUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.plain)
            .disabled(!canGoUp)
            .keyboardShortcut(.upArrow, modifiers: .command)
            .help("上一级 ⌘↑")

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
