import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 已排入一次延迟退出流程；期间再次收到回调只返回 `.terminateLater`，避免重复 reply。
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DMGSessionModel.shared.offerAssociationIfNeeded()
        DMGSessionModel.shared.reportPendingBackups()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "dmg" {
            DMGSessionModel.shared.open(dmgURL: url)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 恢复单窗口语义：关掉最后一个窗口就退出。若有挂载或收尾在进行，
        // applicationShouldTerminate 会等它们结束再回复系统。
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = DMGSessionModel.shared
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
