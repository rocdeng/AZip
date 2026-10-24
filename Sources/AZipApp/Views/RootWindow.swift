import AZipCore
import SwiftUI
import UniformTypeIdentifiers

struct RootWindow: View {
    @ObservedObject var model: DMGSessionModel
    @StateObject private var archive = ArchiveSession.shared
    @State private var isDropTargeted = false
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        // 毛玻璃由 `WindowConfigurator` 在 AppKit 层铺满整个窗口；
        // 这里不再放任何不透明或材质背景，否则会盖住底层的 behindWindow 模糊。
        Group {
            if let job = archive.job {
                ExtractView(session: archive, job: job)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // 内容与底部安装栏上下排布：按钮占独立一条，不叠在 DMG 内容上。
                VStack(spacing: 0) {
                    content
                        .padding(.top, DMGSessionModel.titleBarInset)
                    BottomBar(model: model)
                }
            }
        }
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
                },
                shouldClose: {
                    // 安装期间关窗会中断 ditto 并从源卷卸载，留下暂存残片。
                    guard !model.isInstalling else {
                        model.warnInstallInProgress()
                        return false
                    }
                    return true
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
        .onAppear {
            // 注册设置窗口入口；直接启动时由 AppDelegate 触发。
            SettingsWindow.opener = { openSettings() }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.accentColor.opacity(0.08))
                    )
                    .allowsHitTesting(false)
            }
        }
        .sheet(item: $model.pendingApps) { selection in
            InstallTargetSheet(
                entries: selection.entries,
                onSelect: { entry in
                    model.installDirectly(entry)
                },
                onCancel: { model.pendingApps = nil }
            )
        }
        .sheet(item: $model.pendingConflict) { request in
            InstallConflictSheet(
                appName: request.appURL.lastPathComponent,
                onConfirm: {
                    model.confirmConflict()
                },
                onCancel: { model.pendingConflict = nil }
            )
        }
        .sheet(isPresented: $model.showAssociationSheet) {
            AssociationSheet()
        }
    }

    /// 接收拖入的 `.dmg`：只处理第一个合法磁盘映像。
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let nsURL = item as? NSURL {
                url = nsURL as URL
            } else {
                url = nil
            }
            guard let url else { return }
            let ext = url.pathExtension.lowercased()
            guard ext == "dmg" || ArchiveSession.supportedExtensions.contains(ext) else {
                return
            }
            Task { @MainActor in
                if ext == "dmg" {
                    DMGSessionModel.shared.open(dmgURL: url)
                } else {
                    ArchiveSession.shared.extract(url: url)
                }
            }
        }
        return true
    }

    /// 未打开文件时只显示 "AZip"，打开后显示 "AZip - 文件名"。
    private var windowTitle: String {
        if let job = archive.job {
            return "AZip - \(job.sourceURL.lastPathComponent)"
        }
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
            // 直接启动时主窗口就是设置界面，不显示空白的挂载占位。
            AssociationSettingsPane()
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
