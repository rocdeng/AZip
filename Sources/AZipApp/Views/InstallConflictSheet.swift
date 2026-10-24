import SwiftUI

struct InstallConflictSheet: View {
    let appName: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(NSLocalizedString("应用程序已存在", comment: ""))
                .font(.headline)
            Text(
                String(
                    format: NSLocalizedString("「%@」已在「应用程序」文件夹中。覆盖安装会把旧版本移到废纸篓。", comment: ""),
                    appName
                )
            )
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button(NSLocalizedString("取消", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("覆盖安装", comment: ""), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
