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

            Text("版本 \(version)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            Text("双击磁盘映像一键安装应用，双击压缩包直接解压。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)
                .padding(.top, 14)

            VStack(alignment: .leading, spacing: 8) {
                Text("作者")
                    .font(.system(size: 11, weight: .semibold))
                Text("dengpeng")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Text("致谢")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.top, 4)
                Text("解压能力由 macOS 自带的 bsdtar / libarchive 提供（BSD 2-Clause 许可）。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("磁盘映像挂载与安装使用系统组件 hdiutil、ditto。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.top, 20)

            Spacer(minLength: 16)

            Button("好") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 20)
        }
        .frame(width: 380, height: 430)
    }
}
