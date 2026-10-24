import AppKit
import Foundation
import SwiftUI
import AZipCore

enum SessionState: Sendable {
    case idle
    case mounting
    case browsing(entries: [VolumeEntry], layout: DMGWindowLayout?)
    case installing(app: URL, progress: Double)
    /// 加密磁盘映像：等待用户输入密码，`message` 为上一次尝试的失败原因。
    case needsPassword(url: URL, message: String?)
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

    @Published var language: AppLanguage = AppLanguage.current {
        didSet {
            guard oldValue != language else { return }
            AppLanguage.current = language
        }
    }

    @Published private(set) var state: SessionState = .idle

    /// 本次启动是否由打开文件触发。为 true 时会话结束后直接退出，
    /// 不再回落显示设置界面；设置只属于「无参数直接运行」的场景。
    var launchedWithFile = false

    /// 从挂载卷内复制出来的临时 dmg，收尾时删除（仅限本应用创建的文件）。
    private var nestedTemporaryDMG: URL?

    /// 安装取消标志。
    private let installCancelFlag = CancelFlag()

    @Published private(set) var mount: MountResult?
    @Published private(set) var dmgName: String = "AZip"
    @Published private(set) var navigationStack: [URL] = []

    /// 浏览历史（绝对路径），供前进/后退使用。
    private var history: [URL] = []
    private var historyIndex: Int = -1

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex >= 0 && historyIndex < history.count - 1 }
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
    /// 打开新映像时未能退出的旧卷；下次打开/关闭时重试卸载，避免卷永久悬挂。
    private var orphanedMounts: [MountResult] = []
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
        case .idle, .browsing, .failed, .needsPassword:
            return false
        }
    }

    /// 安装期间拒绝退出/关窗时向用户说明原因。
    func warnInstallInProgress() {
        banner = BannerMessage(
            text: NSLocalizedString("正在安装，请等待完成后再退出", comment: ""),
            isError: true
        )
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
            text: String(
                format: NSLocalizedString("上次安装未完成，旧版本备份位于：%@", comment: ""),
                backups[0].path
            ),
            isError: true
        )
    }

    func open(dmgURL: URL) {
        // 安装（含安装后的卸载）期间切换会话会卸载源卷，中断正在读取的复制，
        // 且安装任务的错误会因令牌过期被吞掉。此时直接拒绝，不碰令牌与挂载。
        guard !isInstallInFlight else {
            banner = BannerMessage(
                text: NSLocalizedString("正在安装，请等待完成后再打开其他磁盘映像", comment: ""),
                isError: true
            )
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

    private func performOpen(_ initialURL: URL, token: UUID) async {
        guard token == sessionToken else { return }

        // 如果 dmg 位于当前挂载卷内（嵌套映像），必须先复制到临时目录：
        // 后面会卸载源卷，原路径随即失效。
        var dmgURL = initialURL
        if let current = mount,
           initialURL.path.hasPrefix(current.mountPoint.path + "/") {
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "azip-nested-\(UUID().uuidString).dmg"
            )
            if (try? FileManager.default.copyItem(at: initialURL, to: temp)) != nil {
                dmgURL = temp
                nestedTemporaryDMG = temp
            }
        }

        // 上次打开时未能退出的卷：先重试一次，成功则不再保留。
        if !orphanedMounts.isEmpty {
            await retryOrphanedMounts()
            guard token == sessionToken else { return }
        }

        // 只退出本次操作开始时捕获的那个卷，绝不退出“当前 mount”指向的其他会话卷。
        if let previousMount = mount {
            mount = nil
            do {
                try await DiskImageMounter.detach(previousMount)
            } catch {
                // 保留引用，下次打开/关闭时重试；不能静默丢弃，否则卷永久悬挂。
                orphanedMounts.append(previousMount)
                guard token == sessionToken else { return }
                banner = BannerMessage(
                    text: String(
                        format: NSLocalizedString("无法推出上一个磁盘映像：%@。将在下次打开或关闭时重试。", comment: ""),
                        describe(error)
                    ),
                    isError: true
                )
            }
            guard token == sessionToken else { return }
        }

        // 加密映像先向用户要密码，不直接挂载（否则 hdiutil 会弹系统对话框或失败）。
        if await DiskImageMounter.isEncrypted(dmgURL) {
            guard token == sessionToken else { return }
            state = .needsPassword(url: dmgURL, message: nil)
            return
        }

        await performMount(dmgURL, password: nil, token: token)
    }

    /// 用户提交密码后继续挂载。
    func submitPassword(_ password: String) {
        guard case let .needsPassword(url, _) = state else { return }
        let token = sessionToken
        state = .mounting
        Task { await performMount(url, password: password, token: token) }
    }

    func cancelPasswordPrompt() {
        guard case .needsPassword = state else { return }
        state = .idle
    }

    private func performMount(_ dmgURL: URL, password: String?, token: UUID) async {
        var attached: MountResult?
        do {
            let result = try await DiskImageMounter.attach(dmgURL, password: password)
            attached = result

            guard token == sessionToken else {
                // 已被更新的 open 取代：退出自己刚挂载的卷后静默返回。
                try? await DiskImageMounter.detach(result)
                return
            }
            mount = result

            let document = await Self.loadDocument(at: result.mountPoint)
            guard token == sessionToken else {
                // 读取期间会话已被取代（例如关闭）：退出自己刚挂载的卷后返回。
                if mount == result { mount = nil }
                try? await DiskImageMounter.detach(result)
                return
            }
            let parsedLayout = DMGWindowLayout.make(mountPoint: result.mountPoint, document: document)
            let entries = try VolumeScanner.scan(directory: result.mountPoint)

            rootEntries = entries
            layout = parsedLayout
            history = [result.mountPoint]
            historyIndex = 0
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
            if password != nil {
                // 留在密码输入界面允许重试；原始的 hdiutil/diskutil 报错对用户没有意义。
                state = .needsPassword(
                    url: dmgURL,
                    message: NSLocalizedString(
                        "密码不正确，或该磁盘映像有额外保护，无法解锁。",
                        comment: ""
                    )
                )
            } else {
                state = .failed(describe(error))
            }
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
            // 双击具体应用就直接装它，不再弹选择面板。
            startInstall(entry.url, overwrite: false)
        case .file:
            // DMG 里嵌套的磁盘映像：直接用本应用接力打开。
            if entry.url.pathExtension.lowercased() == "dmg" {
                open(dmgURL: entry.url)
            } else {
                NSWorkspace.shared.open(entry.url)
            }
        case .symbolicLink:
            NSWorkspace.shared.open(entry.url)
        }
    }

    private func performEnter(_ url: URL, token: UUID) async {
        guard token == sessionToken else { return }
        loadDirectory(url, recordHistory: true)
    }

    func goUp() {
        // 安装期间禁止导航：导航会把状态从 `.installing` 拉回 `.browsing`，
        // 让安装按钮在 ditto 仍在运行时重新可用。
        guard !isInstallInFlight, let current = currentDirectory, let mount else { return }
        let parent = current.deletingLastPathComponent()
        guard parent.path.hasPrefix(mount.mountPoint.path) else { return }
        loadDirectory(parent, recordHistory: true)
    }

    func goBackToRoot() {
        guard !isInstallInFlight, let mount else { return }
        loadDirectory(mount.mountPoint, recordHistory: true)
    }

    func goBack() {
        guard !isInstallInFlight, canGoBack else { return }
        historyIndex -= 1
        loadDirectory(history[historyIndex], recordHistory: false)
    }

    func goForward() {
        guard !isInstallInFlight, canGoForward else { return }
        historyIndex += 1
        loadDirectory(history[historyIndex], recordHistory: false)
    }

    private func recordHistory(_ url: URL) {
        if historyIndex >= 0, historyIndex < history.count - 1 {
            history.removeSubrange((historyIndex + 1)...)
        }
        if history.last == url {
            historyIndex = history.count - 1
            return
        }
        history.append(url)
        historyIndex = history.count - 1
    }

    /// 加载目录并同步更新导航栈、历史与视图状态。
    private func loadDirectory(_ url: URL, recordHistory shouldRecord: Bool) {
        guard let mount, url.path.hasPrefix(mount.mountPoint.path) else { return }

        var stack: [URL] = []
        var cursor = url
        while cursor.path != mount.mountPoint.path {
            stack.insert(cursor, at: 0)
            let parent = cursor.deletingLastPathComponent()
            guard parent.path != cursor.path else { break }
            cursor = parent
        }
        navigationStack = stack

        do {
            let entries = try VolumeScanner.scan(directory: url)
            if url.path == mount.mountPoint.path {
                rootEntries = entries
                state = .browsing(entries: entries, layout: layout)
            } else {
                state = .browsing(entries: entries, layout: nil)
            }
            if shouldRecord { recordHistory(url) }
        } catch {
            banner = BannerMessage(
                text: NSLocalizedString("无法读取目录", comment: ""),
                isError: true
            )
        }
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
            banner = BannerMessage(
                text: NSLocalizedString("无法读取目录", comment: ""),
                isError: true
            )
        }
    }

    // MARK: - Install

    /// 底部按钮触发：优先按 DMG 文件名推断目标应用，推断不出才让用户选。
    func requestInstallFromBar() {
        guard !isInstallInFlight else { return }
        let candidates = rootApplications
        switch candidates.count {
        case 0:
            return
        case 1:
            startInstall(candidates[0].url, overwrite: false)
        default:
            if let match = bestMatch(forDMGName: dmgName, among: candidates) {
                startInstall(match.url, overwrite: false)
            } else {
                pendingApps = AppSelection(entries: candidates)
            }
        }
    }

    /// 用 DMG 文件名匹配候选应用：完整包含优先，其次按词重叠；
    /// 最高分并列或完全没有交集时返回 nil（交给用户选择）。
    private func bestMatch(forDMGName dmgName: String, among apps: [VolumeEntry]) -> VolumeEntry? {
        let base = (dmgName as NSString)
            .deletingPathExtension
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        let baseWords = Set(base.split(separator: " ").map(String.init))

        var scored: [(app: VolumeEntry, score: Int)] = []
        for app in apps {
            let name = (app.name as NSString)
                .deletingPathExtension
                .lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
            if base.contains(name), !name.isEmpty {
                scored.append((app, 1000 + name.count))
                continue
            }
            let words = Set(name.split(separator: " ").map(String.init))
            let overlap = baseWords.intersection(words).count
            if overlap > 0 {
                scored.append((app, overlap))
            }
        }

        scored.sort { $0.score > $1.score }
        guard let best = scored.first else { return nil }
        if scored.count > 1, scored[1].score == best.score { return nil }
        return best.app
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

        // 先做冲突检查：有同名应用时直接弹确认框，
        // 不要先隐藏主窗口显示进度浮窗再退回来，那样界面会闪一下。
        let targetURL = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(appURL.lastPathComponent)
        if !overwrite, FileManager.default.fileExists(atPath: targetURL.path) {
            pendingConflict = ConflictRequest(appURL: appURL)
            return
        }

        let token = sessionToken
        let mountedVolume = mount
        installCancelFlag.reset()
        isInstallInFlight = true
        state = .installing(app: appURL, progress: 0)

        // 与解压共用同一个独立浮窗。
        updateInstallPanel(appURL: appURL, progress: 0, finished: false)
        let mainWindow = NSApp.windows.first {
            $0.identifier?.rawValue == "AZipMainWindow"
        } ?? NSApp.windows.first {
            $0.canBecomeMain && !($0 is NSPanel) && !$0.isSheet
        }
        ExtractionWindowController.shared.show(over: mainWindow)

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
                                self.updateInstallPanel(
                                    appURL: appURL,
                                    progress: value,
                                    finished: false
                                )
                            }
                        }
                    },
                    isCancelled: { [installCancelFlag] in installCancelFlag.isSet }
                )
                guard token == self.sessionToken else { return }
                self.banner = BannerMessage(
                    text: String(
                        format: NSLocalizedString("已安装 %@", comment: ""),
                        installed.lastPathComponent
                    ),
                    isError: false
                )

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
                        text: String(
                            format: NSLocalizedString("已安装，但无法推出磁盘映像：%@", comment: ""),
                            self.describe(detachError)
                        ),
                        isError: true
                    )
                    self.reloadCurrent()
                } else {
                    // 安装与卸载都已完成：浮窗显示完成，短暂停留后退出，
                    // 不再把主窗口切回设置界面。
                    self.updateInstallPanel(appURL: appURL, progress: 1, finished: true)
                    // 与系统拷贝完成后一致的提示音。
                    NSSound(named: NSSound.Name("Submarine"))?.play()
                    self.mount = nil
                    self.rootEntries = []
                    self.navigationStack = []
                    self.layout = nil
                    // 先复位安装标志，否则 applicationShouldTerminate 会拦下退出。
                    self.isInstallInFlight = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.4))
                        TaskPanelModel.shared.update(nil)
                        ExtractionWindowController.shared.close()
                        NSApp.terminate(nil)
                        // 兜底：若终止被某处拦下，3 秒后强制退出，避免残留空窗口。
                        try? await Task.sleep(for: .seconds(3))
                        exit(0)
                    }
                }
            } catch InstallError.cancelled {
                guard token == self.sessionToken else { return }
                self.closeInstallPanel()
                self.banner = BannerMessage(
                    text: NSLocalizedString("已取消安装", comment: ""),
                    isError: false
                )
                self.reloadCurrent()
                self.leaveInstallingIfNeeded()
            } catch InstallError.conflict(_) {
                guard token == self.sessionToken else { return }
                self.closeInstallPanel()
                self.pendingConflict = ConflictRequest(appURL: appURL)
                self.reloadCurrent()
                self.leaveInstallingIfNeeded()
            } catch {
                guard token == self.sessionToken else { return }
                self.closeInstallPanel()
                self.banner = BannerMessage(text: self.describe(error), isError: true)
                self.reloadCurrent()
                self.leaveInstallingIfNeeded()
            }
        }
    }

    /// 新会话开始时清掉上一轮的提示（例如「已安装 Xxx」）。
    func clearBanner() {
        banner = nil
    }

    /// 用户点击浮窗的取消按钮。
    func cancelInstall() {
        installCancelFlag.set()
    }

    private func updateInstallPanel(appURL: URL, progress: Double, finished: Bool) {
        let name = appURL.deletingPathExtension().lastPathComponent
        let title = finished
            ? String(format: NSLocalizedString("AZip - 已安装 %@", comment: ""), name)
            : String(format: NSLocalizedString("AZip - 正在安装 %@", comment: ""), name)
        let detail = finished
            ? NSLocalizedString("安装完成", comment: "")
            : String(
                format: NSLocalizedString("%d%% · 正在复制到应用程序", comment: ""),
                Int((progress * 100).rounded())
            )
        TaskPanelModel.shared.update(
            TaskPanelState(
                kind: .installing,
                iconURL: appURL,
                title: title,
                detail: detail,
                progress: progress,
                isFinished: finished
            )
        )
    }

    /// 关闭安装浮窗并把主窗口带回前台（冲突/失败时继续用主界面）。
    private func closeInstallPanel() {
        TaskPanelModel.shared.update(nil)
        ExtractionWindowController.shared.close()
        NSApp.windows.first { $0.identifier?.rawValue == "AZipMainWindow" }?
            .makeKeyAndOrderFront(nil)
    }

    // MARK: - Teardown

    /// 关闭当前会话：重置全部会话状态并退出本次会话挂载的卷。
    /// 由应用层在窗口关闭 / 进程终止时 `await` 调用。
    func closeSession() async {
        defer { removeNestedTemporaryCopy() }
        history.removeAll()
        historyIndex = -1
        // 安装期间关闭会话会中断 ditto 并从源卷卸载，留下暂存残片。
        // 调用方已有守卫，这里再兜底一次，防止新的调用路径绕过检查。
        guard !isInstallInFlight else {
            warnInstallInProgress()
            return
        }

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

        if let mountedVolume {
            do {
                try await DiskImageMounter.detach(mountedVolume)
            } catch {
                guard token == sessionToken else { return }
                banner = BannerMessage(
                    text: String(
                        format: NSLocalizedString("无法推出磁盘映像：%@", comment: ""),
                        describe(error)
                    ),
                    isError: true
                )
            }
        }

        // 顺带重试此前未能退出的卷。
        await retryOrphanedMounts()
    }

    private func leaveInstallingIfNeeded() {
        if case .installing = state {
            state = .idle
        }
    }

    // MARK: - Helpers

    /// 在 MainActor 之外读取并解析 `.DS_Store`。
    ///
    /// 恶意 dmg 可以把 `.DS_Store` 放成 FIFO 或超大文件：对 FIFO 的 `open(2)` 会永久阻塞，
    /// 因此先用资源值确认是普通文件且大小有界，再把读 I/O 放到协作线程池执行。
    nonisolated static func loadDocument(at mountPoint: URL) async -> DSStoreDocument {
        // 超过 8 MiB 视为恶意/异常，直接忽略。
        let maximumDSStoreSize = 8 * 1024 * 1024
        let url = mountPoint.appendingPathComponent(".DS_Store")
        guard let values = try? url.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .totalFileSizeKey]
        ),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let size = values.fileSize ?? values.totalFileSize,
            size >= 0,
            size <= maximumDSStoreSize else {
            return DSStoreDocument()
        }

        guard let data = try? Data(contentsOf: url) else { return DSStoreDocument() }
        return DSStoreReader.parse(data)
    }

    /// 重试卸载上次打开时未能退出的卷；仍失败的继续保留。
    private func retryOrphanedMounts() async {
        guard !orphanedMounts.isEmpty else { return }
        var remaining: [MountResult] = []
        for orphan in orphanedMounts {
            do {
                try await DiskImageMounter.detach(orphan)
            } catch {
                remaining.append(orphan)
            }
        }
        orphanedMounts = remaining
    }

    /// DMG 声明的窗口尺寸只覆盖内容区；窗口还要容纳标题栏与底部安装栏。
    static let titleBarInset: CGFloat = 12
    static let bottomBarInset: CGFloat = 78

    private func windowContentSize(for size: CGSize) -> NSSize {
        let insets = Self.titleBarInset + Self.bottomBarInset
        var width = size.width
        var height = size.height + insets

        // 不能超过屏幕可用区域，否则底部安装按钮会被顶出屏幕。
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            width = min(width, visible.width - 40)
            height = min(height, visible.height - 40)
        }
        return NSSize(width: width, height: height)
    }

    private func resizeWindow(to size: CGSize) {
        // WindowGroup 可能同时存在多个主窗口，全部按同一尺寸处理，
        // 否则用户看到的那扇可能不是被调整的那扇。
        let windows = NSApp.windows.filter {
            $0.identifier?.rawValue == "AZipMainWindow"
        }
        guard !windows.isEmpty else {
            pendingWindowSize = size
            return
        }
        pendingWindowSize = nil
        for window in windows {
            window.setContentSize(windowContentSize(for: size))
            window.center()
        }
    }

    /// 由应用层在真实主窗口出现后调用，应用暂存的窗口尺寸。
    func applyPendingWindowSize(to window: NSWindow) {
        guard let size = pendingWindowSize else { return }
        pendingWindowSize = nil
        window.setContentSize(windowContentSize(for: size))
        window.center()
    }

    /// 清掉为打开嵌套 dmg 而生成的临时副本。
    private func removeNestedTemporaryCopy() {
        guard let url = nestedTemporaryDMG else { return }
        nestedTemporaryDMG = nil
        try? FileManager.default.removeItem(at: url)
    }

    private func describe(_ error: Error) -> String {
        switch error {
        case MountError.toolFailed(_, let message):
            return String(
                format: NSLocalizedString("无法打开该磁盘映像。\n%@", comment: ""),
                message
            )
        case MountError.noMountPointFound:
            return NSLocalizedString("无法打开该磁盘映像，文件可能已损坏。", comment: "")
        case ProcessRunnerError.timedOut:
            return NSLocalizedString("操作超时，请稍后重试。", comment: "")
        case ProcessRunnerError.launchFailed(let message):
            return String(
                format: NSLocalizedString("无法启动系统工具。\n%@", comment: ""),
                message
            )
        case InstallError.invalidSource:
            return NSLocalizedString("所选项目不是有效的应用程序。", comment: "")
        case InstallError.targetNotWritable:
            return NSLocalizedString("没有权限写入应用程序文件夹，请在访达中手动拖拽安装。", comment: "")
        case InstallError.conflict(let appURL):
            return String(
                format: NSLocalizedString("目标位置已存在“%@”，请确认是否覆盖。", comment: ""),
                appURL.lastPathComponent
            )
        case InstallError.copyFailed(let message):
            return String(
                format: NSLocalizedString("安装失败：%@", comment: ""),
                message
            )
        case InstallError.moveFailed(let message):
            return String(
                format: NSLocalizedString("安装失败：%@", comment: ""),
                message
            )
        default:
            return String(
                format: NSLocalizedString("发生未知错误（%@）", comment: ""),
                "\(type(of: error))"
            )
        }
    }
}
