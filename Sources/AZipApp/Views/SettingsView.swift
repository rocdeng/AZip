import AZipCore
import SwiftUI

struct SettingsView: View {
    @AppStorage("didOfferFileAssociation") private var didOffer = false

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
                        didOffer = false
                        message = "下次启动时会再次提示"
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
            message = "已恢复系统默认"
        } catch {
            message = "恢复失败：\(error)"
        }
        refresh()
    }
}
