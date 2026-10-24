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
    /// 当前 `openTask` 的标识；任务结束时仅当标识仍匹配才清空 `openTask`。
    private var openTaskID: UUID?
    /// 收尾（卸载）正在进行中。
    private var isTearingDown = false
    /// 正在执行的收尾任务；重复调用 `closeSession` 时 join 它，避免提前返回。
    private var teardownTask: Task<Void, Never>?
    /// 安装成功后退出源卷的任务；退出流程据此等待卸载完成。
    /// 返回值为卸载错误：nil 表示已卸载，非 nil 表示失败、卷仍挂载。
    private var detachTask: Task<Error?, Never>?
    /// 安装是否仍在进行（含安装成功后的卸载阶段）。
    /// 安装状态的单一事实来源：不能用 `state` 推断，因为卸载期间必须保持安装态，
    /// 否则会出现“安装按钮可点、⌘Q 可退出、可切换磁盘映像”的竞态。
    @Published private(set) var isInstallInFlight = false
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

    /// 安装（复制）正在进行中，或安装成功后的卸载尚未结束。
    /// 退出/关窗/切换磁盘映像流程据此拒绝中断安装。
    var isInstalling: Bool {
        isInstallInFlight
    }

    /// 有任何挂载、挂载中、卸载中或进行中的安装时都为 true。
    /// 退出流程据此决定是否等待收尾，避免留下无人回收的挂载卷。
    var isBusy: Bool {
        if mount != nil || isTearingDown || openTask != nil || detachTask != nil || isInstallInFlight {
            return true
        }
        switch state {
        case .mounting, .installing:
            return true
        case .idle, .browsing, .failed:
            return false
        }
    }

    /// 安装期间拒绝退出/关窗时向用户说明原因。
    func warnInstallInProgress() {
        banner = BannerMessage(text: "正在安装，请等待完成后再退出", isError: true)
    }

    // MARK: - Lifecycle

    func offerAssociationIfNeeded() {
        guard !associationPromptShown else { return }
        associationPromptShown = true
        guard !UserDefaults.standard.bool(forKey: "didOfferFileAssociation") else { return }
        presentAssociationPrompt()
    }

    /// 设置页「重新显示关联提示」：立即弹出面板，无需重启应用。
    /// 展示即视为已询问过，保持 `didOfferFileAssociation` 的既有语义。
    func presentAssociationPrompt() {
        associationPromptShown = true
        // 在弹出面板之前就落盘，避免面板展示期间应用退出后重复弹出。
        UserDefaults.standard.set(true, forKey: "didOfferFileAssociation")
        showAssociationSheet = true
    }

    func reportPendingBackups() {
        let backups = AppInstaller.pendingBackups(in: URL(fileURLWithPath: "/Applications"))
        guard !backups.isEmpty else { return }
        banner = BannerMessage(
            text: "上次安装未完成，旧版本备份位于：\(backups[0].path)",
            isError: true
        )
    }

    func open(dmgURL: URL) {
        // 安装（含安装后的卸载）期间切换会话会卸载源卷，中断正在读取的复制，
        // 且安装任务的错误会因令牌过期被吞掉。此时直接拒绝，不碰令牌与挂载。
        guard !isInstallInFlight else {
            banner = BannerMessage(text: "正在安装，请等待完成后再打开其他磁盘映像", isError: true)
            return
        }

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
        //
        // 这里刻意不 cancel 上一个 open：ProcessRunner 只在超时时终止子进程，没有取消处理，
        // 取消只会从内部的 Task.sleep 抛出 CancellationError，让 attach 在上抛错的同时
        // 继续由 hdiutil 完成挂载——`performOpen` 的 catch 拿不到 MountResult，卷就永久悬挂。
        // 因此改为纯串行等待；被取代的 open 由 `performOpen` 开头的令牌检查直接返回，
        // 若它恰好已经挂载完成，则在同一处令牌检查里退出自己挂的卷。
        let previous = openTask
        let taskID = UUID()
        openTaskID = taskID
        openTask = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            await self.performOpen(dmgURL, token: token)
            self.finishOpenTask(taskID)
        }
    }

    /// 任务结束时清空 `openTask`，否则已完成（但对象仍被持有）的 open 会让 `isBusy` 永远为 true。
    private func finishOpenTask(_ id: UUID) {
        guard openTaskID == id else { return }
        openTask = nil
        openTaskID = nil
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
        // 安装期间不得导航或再次触发安装：界面虽被进度视图覆盖，
        // 键盘快捷键等路径仍可能到达这里。
        guard !isInstallInFlight else { return }
        switch entry.kind {
        case .folder:
            // 同步捕获令牌：任务可能在新的 open 之后才启动，不能在任务内部再读。
            let token = sessionToken
            Task { await performEnter(entry.url, token: token) }
        case .application:
            requestInstall(entry)
        case .file, .symbolicLink:
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func performEnter(_ url: URL, token: UUID) async {
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
        // 安装期间禁止导航：`reloadCurrent` 会把状态从 `.installing` 拉回 `.browsing`，
        // 让安装按钮在 ditto 仍在运行时重新可用。
        guard !isInstallInFlight, !navigationStack.isEmpty else { return }
        navigationStack.removeLast()
        reloadCurrent()
    }

    func goBackToRoot() {
        guard !isInstallInFlight else { return }
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
        guard !isInstallInFlight else { return }
        let candidates = rootApplications
        if candidates.count > 1 {
            pendingApps = AppSelection(entries: candidates)
        } else {
            startInstall(app.url, overwrite: false)
        }
    }

    /// 由选择面板直接指定要安装的应用（不再重复弹面板）。
    func installDirectly(_ entry: VolumeEntry) {
        guard !isInstallInFlight else { return }
        pendingApps = nil
        startInstall(entry.url, overwrite: false)
    }

    func confirmConflict() {
        guard !isInstallInFlight, let request = pendingConflict else { return }
        pendingConflict = nil
        startInstall(request.appURL, overwrite: true)
    }

    private func startInstall(_ appURL: URL, overwrite: Bool) {
        // 同一时刻只允许一个安装流程，包括安装成功后的卸载阶段。
        // `isInstallInFlight` 是单一事实来源，`.installing` 检查仅作防御。
        guard !isInstallInFlight else { return }
        if case .installing = state { return }
        pendingConflict = nil

        let token = sessionToken
        let mountedVolume = mount
        isInstallInFlight = true
        state = .installing(app: appURL, progress: 0)

        Task { [weak self] in
            guard let self else { return }
            // 所有退出路径（成功、冲突、失败）都必须复位该标志；
            // 成功路径的 `defer` 在卸载 await 之后才执行，因此卸载期间仍为安装态。
            defer { self.isInstallInFlight = false }
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
                            // 迟到的回调不能把已完成的安装重新拉回 .installing。
                            if case .installing = self.state {
                                self.state = .installing(app: appURL, progress: value)
                            }
                        }
                    }
                )
                guard token == self.sessionToken else { return }
                self.banner = BannerMessage(text: "已安装 \(installed.lastPathComponent)", isError: false)

                // 保持 `.installing` 与 `isInstalling == true` 直到卸载完成：
                // 期间安装按钮保持禁用，⌘Q / 关窗 / 打开其他映像都会被拒绝。
                var detachError: Error?
                if let mountedVolume {
                    // 先完成卸载再清 mount：这期间 `isBusy` 仍为 true，
                    // 用户此时 ⌘Q 会等待卸载结束，不会在 detach 前退出。
                    let detachTask = Task { @MainActor [weak self] () -> Error? in
                        do {
                            try await DiskImageMounter.detach(mountedVolume)
                            guard let self else { return nil }
                            if self.mount == mountedVolume { self.mount = nil }
                            self.detachTask = nil
                            return nil
                        } catch {
                            guard let self else { return error }
                            self.detachTask = nil
                            return error
                        }
                    }
                    self.detachTask = detachTask
                    detachError = await detachTask.value
                }
                guard token == self.sessionToken else { return }

                if let detachError {
                    // 卸载失败：保留 mount 以便后续收尾重试，而不是直接丢弃引用。
                    self.banner = BannerMessage(
                        text: "已安装，但无法推出磁盘映像：\(self.describe(detachError))",
                        isError: true
                    )
                    self.reloadCurrent()
                } else {
                    // 安装与卸载都已完成，会话结束：清空根目录条目，
                    // 否则 `.idle` 下 BottomBar 仍会认为有可安装应用。
                    self.mount = nil
                    self.rootEntries = []
                    self.navigationStack = []
                    self.layout = nil
                    self.state = .idle
                }
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
        // 已有收尾在进行时 join 它，绝不另起一份提前返回：退出流程必须等到
        // detach 真正完成才能回复系统，否则进程会在卷卸载前退出。
        if let existing = teardownTask {
            await existing.value
            // 收尾期间若又开了新会话，把它也一并收掉。
            if isBusy {
                await closeSession()
            }
            return
        }

        isTearingDown = true
        let task = Task { @MainActor [weak self] in
            // 在任务体内清除状态，确保 `await task.value` 的调用方恢复时标记已复位。
            defer {
                self?.isTearingDown = false
                self?.teardownTask = nil
            }
            await self?.performCloseSession()
        }
        teardownTask = task
        await task.value
        // 收尾期间若又开了新会话，继续收尾，直到真正空闲再返回。
        if isBusy {
            await closeSession()
        }
    }

    private func performCloseSession() async {
        // 让仍在进行的 open / install 续体失效，避免它们在关闭后继续写状态。
        sessionToken = UUID()
        // 本次关闭操作的令牌：detach 期间若用户又开了新会话，旧会话的错误不能写进新会话。
        let token = sessionToken

        // 不能取消 openTask：ProcessRunner 没有取消处理，取消只会让 attach 在 hdiutil
        // 继续运行时抛错，卷挂上了却没有 MountResult 可以回收。这里等它自然结束后再收尾。
        let inFlight = openTask
        // 安装后的卸载可能正在进行：等它落定，避免对同一卷重复 detach。
        let inFlightDetach = detachTask

        _ = await inFlightDetach?.value

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
        showAssociationSheet = false
        pendingWindowSize = nil

        // 等 in-flight attach 落定，保证不会有卷在会话结束后才挂上。
        _ = await inFlight?.value
        // 等待期间若已开启新会话，它的 openTask 不能被这里清掉。
        if sessionToken == token {
            openTask = nil
        }

        guard let mountedVolume else { return }
        do {
            try await DiskImageMounter.detach(mountedVolume)
        } catch {
            guard token == sessionToken else { return }
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
