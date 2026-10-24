import SwiftUI

@main
struct AZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DMGSessionModel.shared

    var body: some Scene {
        // 单例窗口：`WindowGroup` 会实例化多个窗口，而它们共享同一个
        // `DMGSessionModel.shared`，关掉任一个都会卸载别的窗口正在用的卷。
        Window("AZip", id: "main") {
            RootWindow(model: model)
                .id(model.language)
                .environment(\.locale, model.language.locale)
        }
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
