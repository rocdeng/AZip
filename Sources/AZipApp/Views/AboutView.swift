import AppKit
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 88, height: 88)
                .padding(.top, 26)

            Text("AZip")
                .font(.system(size: 22, weight: .semibold))
                .padding(.top, 10)

            Text(String(format: NSLocalizedString("版本 %@", comment: ""), version))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text(NSLocalizedString("双击磁盘映像一键安装应用，双击压缩包直接解压。", comment: ""))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text(NSLocalizedString("作者", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                Text("dengpeng")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text(NSLocalizedString("致谢", comment: ""))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 4)
                Text(NSLocalizedString("解压能力由 macOS 自带的 bsdtar / libarchive 提供（BSD 2-Clause 许可）。", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(NSLocalizedString("磁盘映像挂载与安装使用系统组件 hdiutil、ditto。", comment: ""))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 20)

            Spacer(minLength: 16)

            Button(NSLocalizedString("好", comment: "")) { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
        .frame(width: 380, height: 430)
    }
}
