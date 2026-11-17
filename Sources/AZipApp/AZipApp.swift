import SwiftUI

@main
struct AZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DMGSessionModel.shared

    var body: some Scene {
        // 用 `WindowGroup` 才能稳定创建窗口（单例 `Window` 在部分系统上启动不建窗）。
        // 「新建窗口」命令已被移除，因此仍然只有一个主窗口。
        WindowGroup("AZip") {
            RootWindow(model: model)
                .id(model.language)
                .environment(\.locale, model.language.locale)
        }
        // 不指定时 SwiftUI 按 900×450 建窗；与设置页尺寸一致，首帧前的摆放失效时也不会闪出宽窗口。
        .defaultSize(width: 520, height: 600)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(NSLocalizedString("打开…", comment: "")) {
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
                .id(model.language)
                .environment(\.locale, model.language.locale)
        }
    }
}
