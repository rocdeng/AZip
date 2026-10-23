import AppKit
import Foundation
import SwiftUI
import AZipCore

enum SessionState: Sendable {
    case idle
    case mounting
    case browsing(entries: [VolumeEntry], layout: DMGWindowLayout?)
    case installing(app: URL, progress: Double)
    case failed(String)
}

struct BannerMessage: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// 多个 `.app` 时的选择面板数据源。
struct AppSelection: Identifiable, Sendable {
    let id = UUID()
    let entries: [VolumeEntry]
}

/// 同名覆盖确认面板数据源。
struct ConflictRequest: Identifiable, Sendable {
    let id = UUID()
    let appURL: URL
}

@MainActor
final class DMGSessionModel: ObservableObject {
    static let shared = DMGSessionModel()

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var mount: MountResult?
    @Published private(set) var dmgName: String = "AZip"
    @Published private(set) var navigationStack: [URL] = []
    @Published var banner: BannerMessage?
    @Published var showAssociationSheet = false
    @Published var pendingApps: AppSelection?
    @Published var pendingConflict: ConflictRequest?

    private var layout: DMGWindowLayout?
    private var associationPromptShown = false
    /// 每次 `open` 都会更新；所有异步续体用它判断自己是否仍属于当前会话。
    private var sessionToken = UUID()
    /// 串行化 `open`，避免两次快速打开同时 attach 导致前一个挂载卷泄漏。
    private var openTask: Task<Void, Never>?
    /// 根目录条目，供 `rootApplications` 使用，不受当前浏览目录影响。
    private var rootEntries: [VolumeEntry] = []
    /// 窗口尚未出现时暂存的尺寸，由 `applyPendingWindowSize(to:)` 应用。
    private var pendingWindowSize: CGSize?

    var currentDirectory: URL? {
        navigationStack.last ?? mount?.mountPoint
    }

    var currentDirectoryName: String {
        if navigationStack.isEmpty {
            return dmgName
        }
        return navigationStack.last?.lastPathComponent ?? dmgName
    }

    var rootApplications: [VolumeEntry] {
        VolumeScanner.applications(in: rootEntries)
    }

    // MARK: - Lifecycle

    func offerAssociationIfNeeded() {
        guard !associationPromptShown else { return }
        associationPromptShown = true
        guard !UserDefaults.standard.bool(forKey: "didOfferFileAssociation") else { return }
        // 在弹出面板之前就落盘，避免面板展示期间应用退出后重复弹出。
        UserDefaults.standard.set(true, forKey: "didOfferFileAssociation")
        showAssociationSheet = true
    }

    func open(dmgURL: URL) {
        // 立刻切换到新会话：旧会话的异步续体从此不再有权写状态。
        sessionToken = UUID()
        let token = sessionToken

        dmgName = dmgURL.lastPathComponent
        navigationStack = []
        rootEntries = []
        layout = nil
        pendingConflict = nil
        pendingApps = nil
        banner = nil
        state = .mounting

        // 串行化打开流程：等上一个 open 完成清理后再开始，避免两个卷同时挂载。
        let previous = openTask
        previous?.cancel()
        openTask = Task { [weak self] in
            await previous?.value
            guard let self, token == self.sessionToken else { return }
            await self.performOpen(dmgURL, token: token)
        }
    }

    private func performOpen(_ dmgURL: URL, token: UUID) async {
        guard token == sessionToken else { return }

        // 只退出本次操作开始时捕获的那个卷，绝不退出“当前 mount”指向的其他会话卷。
        if let previousMount = mount {
            mount = nil
            try? await DiskImageMounter.detach(previousMount)
            guard token == sessionToken else { return }
        }

        var attached: MountResult?
        do {
            let result = try await DiskImageMounter.attach(dmgURL)
            attached = result

            guard token == sessionToken else {
                // 已被更新的 open 取代：退出自己刚挂载的卷后静默返回。
                try? await DiskImageMounter.detach(result)
                return
            }
            mount = result

            let document = readDSStore(at: result.mountPoint)
            let parsedLayout = DMGWindowLayout.make(mountPoint: result.mountPoint, document: document)
            let entries = try VolumeScanner.scan(directory: result.mountPoint)

            rootEntries = entries
            layout = parsedLayout
            state = .browsing(entries: entries, layout: parsedLayout)

            if let parsedLayout {
                resizeWindow(to: parsedLayout.contentSize)
            }
        } catch {
            // 已经挂载但后续步骤（扫描/解析）失败时，必须退出卷，否则卷会永久悬挂。
            if let attached {
                if mount == attached { mount = nil }
                try? await DiskImageMounter.detach(attached)
            }
            guard token == sessionToken else { return }
            mount = nil
            state = .failed(describe(error))
        }
    }

    func enter(_ entry: VolumeEntry) {
        switch entry.kind {
        case .folder:
            Task { await performEnter(entry.url) }
        case .application:
            requestInstall(entry)
        case .file, .symbolicLink:
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func performEnter(_ url: URL) async {
        let token = sessionToken
        guard token == sessionToken else { return }
        do {
            let entries = try VolumeScanner.scan(directory: url)
            guard token == sessionToken else { return }
            navigationStack.append(url)
            state = .browsing(entries: entries, layout: nil)
        } catch {
            guard token == sessionToken else { return }
            banner = BannerMessage(text: "无法打开文件夹", isError: true)
        }
    }

    func goUp() {
        guard !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        reloadCurrent()
    }

    func goBackToRoot() {
        navigationStack.removeAll()
        reloadCurrent()
    }

    private func reloadCurrent() {
        guard let directory = currentDirectory else { return }
        do {
            let entries = try VolumeScanner.scan(directory: directory)
            let activeLayout = navigationStack.isEmpty ? layout : nil
            if navigationStack.isEmpty {
                rootEntries = entries
            }
            state = .browsing(entries: entries, layout: activeLayout)
        } catch {
            banner = BannerMessage(text: "无法读取目录", isError: true)
        }
    }

    // MARK: - Install

    func requestInstall(_ app: VolumeEntry) {
        let candidates = rootApplications
        if candidates.count > 1 {
            pendingApps = AppSelection(entries: candidates)
        } else {
            startInstall(app.url, overwrite: false)
        }
    }

    /// 由选择面板直接指定要安装的应用（不再重复弹面板）。
    func installDirectly(_ entry: VolumeEntry) {
        pendingApps = nil
        startInstall(entry.url, overwrite: false)
    }

    func confirmConflict() {
        guard let request = pendingConflict else { return }
        pendingConflict = nil
        startInstall(request.appURL, overwrite: true)
    }

    private func startInstall(_ appURL: URL, overwrite: Bool) {
        // 同一时刻只允许一个安装流程；失败路径一定会离开 .installing，因此该状态可信。
        if case .installing = state { return }
        pendingConflict = nil

        let token = sessionToken
        let mountedVolume = mount
        state = .installing(app: appURL, progress: 0)

        Task { [weak self] in
            guard let self else { return }
            do {
                let installed = try await AppInstaller.install(
                    InstallRequest(
                        sourceApp: appURL,
                        targetDirectory: URL(fileURLWithPath: "/Applications"),
                        overwrite: overwrite
                    ),
                    progress: { [weak self] value in
                        Task { @MainActor in
                            guard let self, token == self.sessionToken else { return }
                            self.state = .installing(app: appURL, progress: value)
                        }
                    }
                )
                guard token == self.sessionToken else { return }
                self.banner = BannerMessage(text: "已安装 \(installed.lastPathComponent)", isError: false)
                self.reloadCurrent()
                if let mountedVolume {
                    if self.mount == mountedVolume { self.mount = nil }
                    try? await DiskImageMounter.detach(mountedVolume)
                }
                guard token == self.sessionToken else { return }
                self.state = .idle
            } catch InstallError.conflict(_) {
                guard token == self.sessionToken else { return }
                self.pendingConflict = ConflictRequest(appURL: appURL)
                self.reloadCurrent()
                self.leaveInstallingIfNeeded()
            } catch {
                guard token == self.sessionToken else { return }
                self.banner = BannerMessage(text: self.describe(error), isError: true)
                self.reloadCurrent()
                self.leaveInstallingIfNeeded()
            }
        }
    }

    // MARK: - Teardown

    /// 关闭当前会话：重置全部会话状态并退出本次会话挂载的卷。
    /// 由应用层在窗口关闭 / 进程终止时 `await` 调用。
    func closeSession() async {
        // 让仍在进行的 open / install 续体失效，避免它们在关闭后继续写状态。
        sessionToken = UUID()
        openTask?.cancel()
        openTask = nil

        let mountedVolume = mount
        mount = nil
        rootEntries = []
        state = .idle
        navigationStack = []
        dmgName = "AZip"
        layout = nil
        banner = nil
        pendingApps = nil
        pendingConflict = nil

        guard let mountedVolume else { return }
        do {
            try await DiskImageMounter.detach(mountedVolume)
        } catch {
            banner = BannerMessage(text: "无法推出磁盘映像：\(describe(error))", isError: true)
        }
    }

    private func leaveInstallingIfNeeded() {
        if case .installing = state {
            state = .idle
        }
    }

    // MARK: - Helpers

    private func readDSStore(at mountPoint: URL) -> DSStoreDocument {
        let url = mountPoint.appendingPathComponent(".DS_Store")
        guard let data = try? Data(contentsOf: url) else { return DSStoreDocument() }
        return DSStoreReader.parse(data)
    }

    private func resizeWindow(to size: CGSize) {
        guard let window = NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && !($0 is NSPanel)
        }) else {
            pendingWindowSize = size
            return
        }
        pendingWindowSize = nil
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.center()
    }

    /// 由应用层在真实主窗口出现后调用，应用暂存的窗口尺寸。
    func applyPendingWindowSize(to window: NSWindow) {
        guard let size = pendingWindowSize else { return }
        pendingWindowSize = nil
        window.setContentSize(NSSize(width: size.width, height: size.height))
        window.center()
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case MountError.toolFailed(_, let message):
            return "无法打开该磁盘映像。\n\(message)"
        case MountError.noMountPointFound:
            return "无法打开该磁盘映像，文件可能已损坏。"
        case ProcessRunnerError.timedOut:
            return "操作超时，请稍后重试。"
        case ProcessRunnerError.launchFailed(let message):
            return "无法启动系统工具。\n\(message)"
        case InstallError.invalidSource:
            return "所选项目不是有效的应用程序。"
        case InstallError.targetNotWritable:
            return "没有权限写入应用程序文件夹，请在访达中手动拖拽安装。"
        case InstallError.conflict(let appURL):
            return "目标位置已存在“\(appURL.lastPathComponent)”，请确认是否覆盖。"
        case InstallError.copyFailed(let message):
            return "安装失败：\(message)"
        case InstallError.moveFailed(let message):
            return "安装失败：\(message)"
        default:
            return "发生未知错误（\(type(of: error))）"
        }
    }
}
