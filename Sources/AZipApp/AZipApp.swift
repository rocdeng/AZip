import SwiftUI

@main
struct AZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DMGSessionModel.shared

    var body: some Scene {
        // 单窗口：`WindowGroup` 的 ⌘N「新建窗口」会让两个窗口共享同一个
        // `DMGSessionModel.shared`，关闭任一个都会卸载另一个正在使用的卷。
        Window("AZip", id: "main") {
            RootWindow(model: model)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .newItem) {
                Button("打开…") {
                    OpenPanel.openDMG { url in
                        model.open(dmgURL: url)
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
