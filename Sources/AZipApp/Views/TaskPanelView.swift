import AppKit
import SwiftUI

/// 通用进度浮窗内容：解压与安装共用（380×84 横向条）。
struct TaskPanelView: View {
    let state: TaskPanelState
    let onCancel: () -> Void

    var body: some View {
        content
            .frame(width: 380, height: 84)
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(nsImage: TaskIconCache.icon(for: state.iconURL))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if state.isIndeterminate && !state.isFinished {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .frame(height: 6)
                } else {
                    ShimmerProgressBar(progress: state.progress)
                }

                Text(state.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state.isCancellable {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary.opacity(0.85))
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("取消", comment: ""))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}


/// 带流光扫过的进度条：一道高光沿已完成部分循环扫过，裁剪在胶囊内。
///
/// 系统 `ProgressView` / `NSProgressIndicator` 都没有这个样式，只能自己叠。
/// 用 `TimelineView(.animation)` 驱动而不是 `withAnimation(.repeatForever)`：
/// 进度值频繁刷新会让视图重建，前者不会像后者那样反复重启动画。
private struct ShimmerProgressBar: View {
    let progress: Double

    private let bandWidth: CGFloat = 56
    private let period: Double = 1.6

    var body: some View {
        GeometryReader { geometry in
            let filled = max(2, geometry.size.width * progress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.14))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: filled)
                    .overlay {
                        TimelineView(.animation) { context in
                            let phase = context.date
                                .timeIntervalSinceReferenceDate
                                .truncatingRemainder(dividingBy: period) / period
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.65), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: bandWidth)
                            .offset(x: (phase - 0.5) * (filled + bandWidth))
                        }
                        // 必须显式撑满填充条：TimelineView 默认只有内容那么大（56pt），
                        // 光带一 offset 就被裁在自己的小盒子里，完全看不见。
                        .frame(width: filled, height: 6)
                        .clipShape(Capsule())
                    }
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

/// 任务进行中源卷可能被卸载，图标必须在挂载期间取好并缓存。
@MainActor
private enum TaskIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let cached = cache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = image
        return image
    }
}
