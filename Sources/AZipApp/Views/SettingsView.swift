import AppKit
import AZipCore
import SwiftUI

struct SettingsView: View {
    @State private var isDefault = false
    @State private var message: String?

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.dengpeng.AZip"
    }

    var body: some View {
        Form {
            Section("文件关联") {
                HStack {
                    Text("DMG 磁盘映像")
                    Spacer()
                    Text(isDefault ? "已关联" : "未关联")
                        .foregroundStyle(isDefault ? .green : .secondary)
                }

                HStack {
                    Button("设为默认打开方式") {
                        setDefault()
                    }
                    Button("恢复系统默认") {
                        restore()
                    }
                    Button("重新显示关联提示") {
                        DMGSessionModel.shared.presentAssociationPrompt()
                        message = "已显示关联提示"
                    }
                }

                if let message {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 200)
        .onAppear(perform: refresh)
        // 在访达里改了关联后，设置页保持打开也能刷新；onReceive 随视图消失自动取消订阅。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        isDefault = FileAssociationService.isDefault(bundleID: bundleID)
    }

    private func setDefault() {
        do {
            try FileAssociationService.setDefault(bundleID: bundleID)
            message = "已设为默认打开方式"
        } catch {
            message = "设置失败：\(error)"
        }
        refresh()
    }

    private func restore() {
        do {
            try FileAssociationService.restoreSystemDefault()
            message = "已将 .dmg 恢复为系统默认打开方式"
        } catch {
            message = "恢复失败：\(error)"
        }
        refresh()
    }
}
