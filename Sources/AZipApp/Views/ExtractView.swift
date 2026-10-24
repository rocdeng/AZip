import AppKit
import SwiftUI

/// 极简解压界面：文件图标、进度、剩余时间、取消/完成操作。
struct ExtractView: View {
    @ObservedObject var session: ArchiveSession
    let job: ExtractionJob

    var body: some View {
        VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: job.sourceURL.path))
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 76, height: 76)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                        .tint(Color.accentColor)
                        .frame(width: 260)

                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            controls
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 26)
        .frame(width: 430)
    }

    private var title: String {
        switch job.phase {
        case .running:
            return "正在解压「\(job.sourceURL.lastPathComponent)」"
        case .finished:
            return "已完成"
        case .cancelled:
            return "已取消"
        case .failed:
            return "解压失败"
        }
    }

    private var detail: String {
        switch job.phase {
        case .running:
            return remainingTimeText
        case let .finished(url):
            return "已解压到「\(url.lastPathComponent)」"
        case .cancelled:
            return "已停止，未完成的文件保留在目标文件夹中"
        case let .failed(message):
            return message
        }
    }

    private var remainingTimeText: String {
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
        return "\(percent)%  \(remaining)"
    }

    @ViewBuilder
    private var controls: some View {
        switch job.phase {
        case .running:
            HStack(spacing: 12) {
                Button("取消") {
                    session.cancel()
                }
                .keyboardShortcut(.cancelAction)
            }
        case .finished:
            HStack(spacing: 12) {
                Button("在访达中显示") {
                    session.revealInFinder()
                }
                .keyboardShortcut(.defaultAction)
            }
        case .cancelled, .failed:
            HStack(spacing: 12) {
                Button("关闭") {
                    session.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
