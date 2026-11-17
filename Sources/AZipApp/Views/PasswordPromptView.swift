import SwiftUI

/// 加密磁盘映像 / 压缩包的密码输入界面。
struct PasswordPromptView: View {
    let fileName: String
    let message: String?
    /// 标题可区分场景：磁盘映像 / 压缩包。
    var title: String = NSLocalizedString("此磁盘映像已加密", comment: "")
    /// 确认按钮文字：磁盘映像为「解开」，压缩包为「解压」。
    var submitTitle: String = NSLocalizedString("解开", comment: "")
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @State private var isRevealed = false
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock.doc")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.system(size: 13, weight: .semibold))

            Text(fileName)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Group {
                    if isRevealed {
                        TextField(NSLocalizedString("密码", comment: ""), text: $password)
                    } else {
                        SecureField(NSLocalizedString("密码", comment: ""), text: $password)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($isFocused)
                .onSubmit(submit)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(NSLocalizedString("显示密码", comment: ""))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.28))
            )
            .frame(maxWidth: 224)

            if let message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }

            HStack(spacing: 11) {
                Button(NSLocalizedString("取消", comment: ""), action: onCancel)
                    .buttonStyle(PasswordActionButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)

                Button(submitTitle, action: submit)
                    .buttonStyle(PasswordActionButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isFocused = true }
    }

    /// 空密码也允许提交，由上层直接提示密码错误。
    private func submit() {
        onSubmit(password)
        password = ""
    }
}

/// 密码窗口的两个按钮：取消为深色，解开为浅色高亮。
private struct PasswordActionButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color.black.opacity(0.85) : Color.primary)
            .padding(.horizontal, 22)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(prominent ? Color.white.opacity(0.88) : Color.white.opacity(0.12))
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
