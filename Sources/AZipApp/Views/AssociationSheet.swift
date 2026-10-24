import AppKit
import AZipCore
import SwiftUI
import UniformTypeIdentifiers

struct AssociationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("didOfferFileAssociation") private var didOffer = false

    @State private var isChecked = true
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(NSLocalizedString("关联文件格式", comment: ""))
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(for: .diskImage))
                    .resizable()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("DMG 磁盘映像", comment: ""))
                        .font(.system(size: 13))
                    Text(".dmg")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $isChecked)
                    .labelsHidden()
            }
            .padding(10)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))

            Text(NSLocalizedString("勾选后，双击 .dmg 文件将由 AZip 打开。之后可在设置中修改。", comment: ""))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let errorText {
                Text(errorText)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(NSLocalizedString("以后再说", comment: "")) {
                    didOffer = true
                    dismiss()
                }
                Button(NSLocalizedString("确认关联", comment: "")) {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func apply() {
        guard isChecked else {
            didOffer = true
            dismiss()
            return
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dengpeng.AZip"
        do {
            try FileAssociationService.setDefault(bundleID: bundleID)
            // 只有真正设置成功才落盘；失败时保留原标记，用户可以再次尝试。
            didOffer = true
            dismiss()
        } catch {
            errorText = String(format: NSLocalizedString("设置失败：%@", comment: ""), "\(error)")
        }
    }
}
