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
            Text("关联文件格式")
                .font(.system(size: 15, weight: .semibold))

            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(for: .diskImage))
                    .resizable()
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DMG 磁盘映像")
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

            Text("勾选后，双击 .dmg 文件将由 AZip 打开。之后可在设置中修改。")
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
                Button("以后再说") {
                    didOffer = true
                    dismiss()
                }
                Button("确认关联") {
                    apply()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func apply() {
        didOffer = true
        guard isChecked else {
            dismiss()
            return
        }
        let bundleID = Bundle.main.bundleIdentifier ?? "com.dengpeng.AZip"
        do {
            try FileAssociationService.setDefault(bundleID: bundleID)
            dismiss()
        } catch {
            errorText = "设置失败：\(error)"
        }
    }
}
