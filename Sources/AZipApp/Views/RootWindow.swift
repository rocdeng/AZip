import AZipCore
import SwiftUI

struct RootWindow: View {
    @ObservedObject var model: DMGSessionModel

    var body: some View {
        // 毛玻璃由 `WindowConfigurator` 在 AppKit 层铺满整个窗口；
        // 这里不再放任何不透明或材质背景，否则会盖住底层的 behindWindow 模糊。
        content
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            WindowConfigurator(
                title: windowTitle,
                onWindowReady: { window in
                    model.applyPendingWindowSize(to: window)
                },
                onWindowClose: {
                    // `closeSession` 是 async：关窗时在任务里等待卸载完成（对应 spec 7.3）。
                    // 用真实窗口关闭事件而不是 `onDisappear`：SwiftUI 启动时会重建根视图，
                    // `onDisappear` 会在挂载完成前误触发并作废会话令牌。
                    Task { await model.closeSession() }
                }
            )
        )
        .frame(minWidth: 480, minHeight: 320)
        .background { navigationShortcuts }
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

    /// 未打开文件时只显示 "AZip"，打开后显示 "AZip - 文件名"。
    private var windowTitle: String {
        switch model.state {
        case .idle, .failed:
            return "AZip"
        default:
            let name = model.dmgName
            return name.isEmpty || name == "AZip" ? "AZip" : "AZip - \(name)"
        }
    }

    /// 导航栏已移除，只保留键盘快捷键（⌘[ / ⌘↑）。
    private var navigationShortcuts: some View {
        VStack(spacing: 0) {
            Button("返回根目录") { model.goBackToRoot() }
                .keyboardShortcut("[", modifiers: .command)
            Button("上一级") { model.goUp() }
                .keyboardShortcut(.upArrow, modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
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
