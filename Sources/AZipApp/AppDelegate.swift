import AppKit

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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DMGSessionModel.shared.reportPendingBackups()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
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
        // 单窗口语义：关掉最后一个窗口就退出。若有挂载或收尾在进行，
        // applicationShouldTerminate 会等它们结束再回复系统。
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = DMGSessionModel.shared
        // 安装期间退出会中断 ditto 并从源卷卸载，留下暂存残片，必须等安装完成。
        guard !model.isInstalling else {
            model.warnInstallInProgress()
            return .terminateCancel
        }
        guard model.isBusy else { return .terminateNow }
        // 已在等待收尾：只继续等待，不再排第二个 reply。
        guard !isTerminating else { return .terminateLater }
        isTerminating = true

        Task { @MainActor in
            await model.closeSession()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
