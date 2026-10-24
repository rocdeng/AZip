import AppKit
import AZipCore
import SwiftUI

struct InstallTargetSheet: View {
    let entries: [VolumeEntry]
    let onSelect: (VolumeEntry) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(NSLocalizedString("选择要安装的应用程序", comment: ""))
                .font(.headline)

            List(entries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    HStack(spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                            .resizable()
                            .frame(width: 32, height: 32)
                        Text(entry.name)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .frame(height: 240)

            HStack {
                Spacer()
                Button(NSLocalizedString("取消", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}
