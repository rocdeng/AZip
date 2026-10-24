import AppKit
import SwiftUI

/// 解压进度浮窗：横向条状，无标题栏。左侧图标，中间文件名/进度/预估时间，右侧取消。
struct ExtractView: View {
    @ObservedObject var session: ArchiveSession
    let job: ExtractionJob

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: job.sourceURL.path))
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                ProgressView(value: job.progress)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                    .frame(width: 300)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                if isRunning {
                    session.cancel()
                } else {
                    session.dismiss()
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(.secondary.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help(isRunning ? "取消解压" : "关闭")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 560, height: 118)
    }

    private var isRunning: Bool {
        if case .running = job.phase { return true }
        return false
    }

    private var title: String {
        switch job.phase {
        case .running:
            return "正在解压「\(job.sourceURL.lastPathComponent)」"
        case .finished:
            return "解压完成"
        case .cancelled:
            return "已取消"
        case .failed:
            return "解压失败"
        }
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
            return seconds < 60
                ? "\(percent)%  ·  约 \(seconds) 秒"
                : "\(percent)%  ·  约 \(seconds / 60) 分 \(seconds % 60) 秒"
        case let .finished(url):
            return "已解压到「\(url.lastPathComponent)」"
        case .cancelled:
            return "已停止"
        case let .failed(message):
            return message
        }
    }
}
