import SwiftUI

/// 加密磁盘映像的密码输入界面。
struct PasswordPromptView: View {
    let fileName: String
    let message: String?
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.doc")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)

            Text(NSLocalizedString("此磁盘映像已加密", comment: ""))
                .font(.system(size: 13, weight: .semibold))

            Text(fileName)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 300)

            SecureField(NSLocalizedString("密码", comment: ""), text: $password)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .focused($isFocused)
                .onSubmit(submit)

            if let message {
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 300)
            }

            HStack(spacing: 10) {
                Button(NSLocalizedString("取消", comment: ""), action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(NSLocalizedString("解开", comment: ""), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty)
            }
            .padding(.top, 2)
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !password.isEmpty else { return }
        onSubmit(password)
        password = ""
    }
}
