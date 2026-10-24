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
                if isIdle {
                    content
                } else {
                    // DMG 背景图有固定内在尺寸，会把 VStack 撑高、把安装栏顶出窗口；
                    // 这里用 GeometryReader 显式分配：按钮栏固定高度，内容区吃剩余空间。
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            content
                                .padding(.top, DMGSessionModel.titleBarInset)
                                .frame(height: max(160, proxy.size.height - Self.bottomBarHeight))
                                .clipped()
                            BottomBar(model: model)
                                .frame(height: Self.bottomBarHeight)
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(
            WindowConfigurator(
                title: windowTitle,
                hidesWindowChrome: archive.job != nil,
                onWindowReady: { window in
                    if archive.job != nil {
                        // 解压由独立浮窗承载，主窗口不露面。
                        window.orderOut(nil)
                    } else if isIdle {
                        window.setContentSize(NSSize(width: 520, height: 600))
                        window.center()
                    } else {
                        model.applyPendingWindowSize(to: window)
                    }
                },
                onWindowClose: {
                    // SwiftUI 在打开文件等场景会重建窗口，此时也会收到 willClose。
                    // 延迟一拍再判断：若已有新的可见主窗口，说明只是重建，不能卸载卷。
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(500))
                        let hasVisibleMain = NSApp.windows.contains {
                            $0.identifier?.rawValue == "AZipMainWindow" && $0.isVisible
                        }
                        guard !hasVisibleMain else { return }
                        await model.closeSession()
                    }
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
        .frame(
            minWidth: archive.job == nil ? 480 : 360,
            minHeight: archive.job == nil ? 320 : 200
        )
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
        .onChange(of: archive.job?.id) { _, _ in
            // 解压浮窗用小尺寸，结束后回到设置页尺寸。
            let size = archive.job == nil
                ? NSSize(width: 520, height: 600)
                : NSSize(width: 420, height: 240)
            resizeMainWindow(size)
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
            .id(model.language)
            .environment(\.locale, model.language.locale)
        }
        .sheet(item: $model.pendingConflict) { request in
            InstallConflictSheet(
                appName: request.appURL.lastPathComponent,
                onConfirm: {
                    model.confirmConflict()
                },
                onCancel: { model.pendingConflict = nil }
            )
            .id(model.language)
            .environment(\.locale, model.language.locale)
        }
        .sheet(isPresented: $model.showAssociationSheet) {
            AssociationSheet()
                .id(model.language)
                .environment(\.locale, model.language.locale)
        }
    }

    private func resizeMainWindow(_ size: NSSize) {
        guard let window = NSApp.windows.first(
            where: { $0.identifier?.rawValue == "AZipMainWindow" }
        ) ?? NSApp.windows.first(where: { $0.canBecomeMain && !($0 is NSPanel) }) else {
            return
        }
        window.setContentSize(size)
        window.center()
    }

    private static let bottomBarHeight: CGFloat = 70

    private var isIdle: Bool {
        if case .idle = model.state { return true }
        return false
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
            Button(NSLocalizedString("返回根目录", comment: "")) { model.goBackToRoot() }
                .keyboardShortcut("[", modifiers: .command)
            Button(NSLocalizedString("上一级", comment: "")) { model.goUp() }
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
            if model.launchedWithFile {
                // 文件会话已结束（取消密码、卸载完成等）：退出，不回落设置。
                // 若存在错误提示，先停留片刻让用户看到，再退出。
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear {
                        let hasBanner = model.banner != nil
                        Task { @MainActor in
                            try? await Task.sleep(
                                for: .seconds(hasBanner ? 2.0 : 0.15)
                            )
                            NSApp.terminate(nil)
                        }
                    }
            } else {
                AssociationSettingsPane()
            }
        case .mounting:
            ProgressView(NSLocalizedString("正在挂载…", comment: ""))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .needsPassword(url, message):
            PasswordPromptView(
                fileName: url.lastPathComponent,
                message: message,
                onSubmit: { model.submitPassword($0) },
                onCancel: { model.cancelPasswordPrompt() }
            )
        case let .browsing(entries, layout):
            if let layout, model.navigationStack.isEmpty {
                LayoutContentView(layout: layout, entries: entries, onOpen: model.enter)
            } else {
                GridContentView(entries: entries, onOpen: model.enter)
            }
        case .installing(_, let progress):
            ProgressView(NSLocalizedString("正在安装…", comment: ""), value: progress)
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
