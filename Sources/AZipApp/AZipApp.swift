import SwiftUI

@main
struct AZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DMGSessionModel.shared

    var body: some Scene {
        // 用 `WindowGroup` 保证启动时一定有窗口；同时移除「新建窗口」命令，
        // 避免两个窗口共享同一个 `DMGSessionModel.shared` 而互相卸载卷。
        WindowGroup("AZip") {
            RootWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开…") {
                    OpenPanel.openDMG { url in
                        if url.pathExtension.lowercased() == "dmg" {
                            model.open(dmgURL: url)
                        } else {
                            ArchiveSession.shared.extract(url: url)
                        }
                    }
                }
                .keyboardShortcut("o")
                .disabled(model.isInstalling)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
