import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        // 关闭窗口后进程必须继续存活，异步的 closeSession() 才有机会卸载卷。
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = DMGSessionModel.shared
        guard model.mount != nil else { return .terminateNow }

        // 还有卷挂着：先卸载，完成后回复系统。
        Task { @MainActor in
            await model.closeSession()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
