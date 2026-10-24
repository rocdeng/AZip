import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 已排入一次延迟退出流程；期间再次收到回调只返回 `.terminateLater`，避免重复 reply。
    private var isTerminating = false

    /// 本次启动是否收到了要打开的文件；直接运行（无文件参数）时为 false。
    private var didReceiveOpenRequest = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DMGSessionModel.shared.reportPendingBackups()

        // 直接运行 AZip（而不是双击某个文件）时，把设置窗口推到前面，
        // 让用户第一眼就能看到文件关联配置。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, !self.didReceiveOpenRequest else { return }
            guard case .idle = DMGSessionModel.shared.state else { return }
            // 直接运行时不要那个空的主窗口，只显示设置。
            DMGSessionModel.shared.hideMainWindow()
            DMGSessionModel.shared.shouldOpenSettings = true
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        DMGSessionModel.shared.showMainWindow()
        for url in urls {
            let ext = url.pathExtension.lowercased()
            if ext == "dmg" {
                didReceiveOpenRequest = true
                DMGSessionModel.shared.open(dmgURL: url)
            } else if ArchiveSession.supportedExtensions.contains(ext) {
                didReceiveOpenRequest = true
                ArchiveSession.shared.extract(url: url)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 恢复单窗口语义：关掉最后一个窗口就退出。若有挂载或收尾在进行，
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

        // 有挂载、挂载中或卸载中：先等收尾完成，再回复系统。
        Task { @MainActor in
            await model.closeSession()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
