import AppKit
import SwiftUI

/// 安装进度卡片：图标 + 应用名 + 进度条，居中浮在内容之上。
struct InstallProgressView: View {
    let appURL: URL
    let progress: Double

    private var displayName: String {
        appURL.deletingPathExtension().lastPathComponent
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 56, height: 56)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

            Text(
                String(
                    format: NSLocalizedString("正在安装「%@」", comment: ""),
                    displayName
                )
            )
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
                .frame(width: 220)

            Text("\(Int((progress * 100).rounded()))%")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 20, y: 8)
    }
}
