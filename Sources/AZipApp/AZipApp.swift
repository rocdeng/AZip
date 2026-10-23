import SwiftUI

@main
struct AZipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = DMGSessionModel.shared

    var body: some Scene {
        WindowGroup("AZip") {
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
            }
        }

        Settings {
            SettingsView()
        }
    }
}
