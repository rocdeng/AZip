import AppKit
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 已排入一次延迟退出流程；期间再次收到回调只返回 `.terminateLater`，避免重复 reply。
    private var isTerminating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 关掉 AppKit 的窗口状态恢复：一旦系统记下「上次退出时没有窗口」，
        // 之后每次启动都不会再创建主窗口，表现就是“进程在跑但没有任何窗口”。
        UserDefaults.standard.register(defaults: [
            "ApplePersistenceIgnoreState": true,
            "NSQuitAlwaysKeepsWindows": false
        ])
    }

    private var keyObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        DMGSessionModel.shared.reportPendingBackups()

        // 注册 Finder「服务」菜单入口。
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        // 调试入口：AZIP_BROWSE=<path> 启动时直接进入浏览模式。
        if let path = ProcessInfo.processInfo.environment["AZIP_BROWSE"] {
            DMGSessionModel.shared.launchedWithFile = true
            ArchiveBrowseSession.shared.open(URL(fileURLWithPath: path))
            BrowseWindowController.shared.show()
        }
    }

    /// Finder 右键 → 服务 → 「用 AZip 浏览压缩包」
    @objc func browseArchive(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString>
    ) {
        guard
            let items = pboard.readObjects(forClasses: [NSURL.self], options: nil),
            let url = items.first as? URL
        else {
            error.pointee = NSLocalizedString("没有可浏览的压缩包", comment: "") as NSString
            return
        }
        // 服务调用与双击打开同属「由文件启动」：关闭浏览后应退出，
        // 而不是回落到设置界面。
        DMGSessionModel.shared.launchedWithFile = true
        ArchiveBrowseSession.shared.open(url)
        BrowseWindowController.shared.show()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DMGSessionModel.shared.launchedWithFile = true
        DMGSessionModel.shared.clearBanner()
        NSApp.activate(ignoringOtherApps: true)
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "dmg" {
                DMGSessionModel.shared.open(dmgURL: url)
            } else if ArchiveSession.supportedExtensions.contains(ext) {
                ArchiveSession.shared.extract(url: url)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 用户关掉主窗口即退出（设置窗口和 DMG 浏览共用一个主窗口）。
        // 解压/安装的进度浮窗是独立窗口，其关闭不会触发这里。
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = DMGSessionModel.shared
        // 解压/排队进行中不允许退出，否则会丢掉后续任务。
        if ArchiveSession.shared.job != nil {
            Logger(subsystem: "com.dengpeng.AZip", category: "lifecycle")
                .info("terminate blocked: extraction in flight")
            return .terminateCancel
        }
        // 安装期间退出会中断 ditto 并从源卷卸载，留下暂存残片，必须等安装完成。
        guard !model.isInstalling else {
            Logger(subsystem: "com.dengpeng.AZip", category: "lifecycle")
                .info("terminate blocked: installing")
            model.warnInstallInProgress()
            return .terminateCancel
        }
        guard model.isBusy else { return .terminateNow }
        // 已在等待收尾：只继续等待，不再排第二个 reply。
        guard !isTerminating else { return .terminateLater }
        isTerminating = true

        Task { @MainActor in
            // 收尾期间 closeSession 会把状态切回 idle，窗口会闪一下设置界面；
            // 先隐藏窗口再执行收尾。
            for window in NSApp.windows where window.isVisible {
                window.orderOut(nil)
            }
            await model.closeSession()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
