import AppKit
import SwiftUI

/// 解压进度浮窗：无标题栏、无红绿灯，只有图标、进度、文件名与预估时间。
struct ExtractView: View {
    @ObservedObject var session: ArchiveSession
    let job: ExtractionJob

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: job.sourceURL.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.12), radius: 5, y: 2)

                Text(job.sourceURL.lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 260)

                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(width: 240)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 260)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                if isRunning {
                    session.cancel()
                } else {
                    session.dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary.opacity(0.9))
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .padding(.trailing, 10)
        }
        .frame(width: 380, height: 190)
    }

    private var isRunning: Bool {
        if case .running = job.phase { return true }
        return false
    }

    private var detail: String {
        switch job.phase {
        case .running:
            let percent = Int((job.progress * 100).rounded())
            guard job.progress > 0.02 else {
                return "\(percent)%  正在估算剩余时间…"
            }
            let elapsed = Date().timeIntervalSince(job.startedAt)
            let estimated = elapsed / job.progress * (1 - job.progress)
            let seconds = max(1, Int(estimated.rounded()))
            let remaining = seconds < 60
                ? "约 \(seconds) 秒"
                : "约 \(seconds / 60) 分 \(seconds % 60) 秒"
            return "\(percent)%  ·  \(remaining)"
        case .finished:
            return "解压完成"
        case .cancelled:
            return "已取消"
        case let .failed(message):
            return message
        }
    }
}
