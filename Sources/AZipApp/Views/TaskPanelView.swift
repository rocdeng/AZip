import AppKit
import SwiftUI

/// 通用进度浮窗内容：解压与安装共用（380×84 横向条）。
struct TaskPanelView: View {
    @ObservedObject var model = TaskPanelModel.shared
    let onCancel: () -> Void

    var body: some View {
        Group {
            if let state = model.state {
                content(for: state)
            } else {
                Color.clear
            }
        }
        .frame(width: 380, height: 84)
    }

    private func content(for state: TaskPanelState) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: state.iconURL.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(state.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.14))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: max(2, geometry.size.width * state.progress))
                    }
                }
                .frame(height: 6)
                .animation(.easeOut(duration: 0.2), value: state.progress)

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
