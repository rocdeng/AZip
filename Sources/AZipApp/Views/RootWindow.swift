import AZipCore
import SwiftUI

struct RootWindow: View {
    @ObservedObject var model: DMGSessionModel

    var body: some View {
        ZStack {
            VisualEffectBackground(material: .hudWindow)

            VStack(spacing: 0) {
                NavigationBar(
                    title: model.currentDirectoryName,
                    canGoUp: !model.navigationStack.isEmpty,
                    onBackToRoot: model.goBackToRoot,
                    onUp: model.goUp
                )
                Divider().opacity(0.15)
                content
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            WindowConfigurator { window in
                model.applyPendingWindowSize(to: window)
            }
        )
        .frame(minWidth: 480, minHeight: 320)
        .onDisappear {
            // `closeSession` 是 async：关窗时在任务里等待卸载完成（对应 spec 7.3）。
            Task { await model.closeSession() }
        }
        .overlay(alignment: .top) {
            if let banner = model.banner {
                Text(banner.text)
                    .font(.system(size: 11))
                    .foregroundStyle(banner.isError ? Color.red : Color.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 52)
                    .onTapGesture { model.banner = nil }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle:
            placeholder("把 .dmg 文件拖到这里，或按 ⌘O 打开")
        case .mounting:
            ProgressView("正在挂载…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .browsing(entries, layout):
            if let layout, model.navigationStack.isEmpty {
                LayoutContentView(layout: layout, entries: entries, onOpen: model.enter)
            } else {
                GridContentView(entries: entries, onOpen: model.enter)
            }
        case .installing(_, let progress):
            ProgressView("正在安装…", value: progress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            placeholder(message)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
