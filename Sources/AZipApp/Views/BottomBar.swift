import AZipCore
import SwiftUI

struct BottomBar: View {
    @ObservedObject var model: DMGSessionModel

    private var isInstalling: Bool {
        model.isInstalling
    }

    var body: some View {
        HStack(spacing: 10) {
            if case .browsing = model.state {
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                if let first = model.rootApplications.first {
                    model.requestInstall(first)
                }
            } label: {
                Label("安装应用", systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.rootApplications.isEmpty || isInstalling)
            .keyboardShortcut("i", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var statusText: String {
        let count = model.rootApplications.count
        switch count {
        case 0: return "此磁盘映像没有可安装的应用程序"
        case 1: return "可安装：\(model.rootApplications[0].name)"
        default: return "\(count) 个应用程序可安装"
        }
    }
}
