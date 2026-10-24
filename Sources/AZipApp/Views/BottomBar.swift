import AZipCore
import SwiftUI

struct BottomBar: View {
    @ObservedObject var model: DMGSessionModel

    private var isDisabled: Bool {
        model.rootApplications.isEmpty || model.isInstalling
    }

    var body: some View {
        ZStack {
            HStack {
                BackForwardControl(
                    canGoBack: model.canGoBack,
                    canGoForward: model.canGoForward,
                    onBack: { model.goBack() },
                    onForward: { model.goForward() }
                )
                Spacer()
            }

            Button {
                if let first = model.rootApplications.first {
                    model.requestInstall(first)
                }
            } label: {
                label
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .help(NSLocalizedString("把应用安装到「应用程序」文件夹", comment: ""))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var label: some View {
        HStack(spacing: 7) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
            Text(NSLocalizedString("安装应用", comment: ""))
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 28)
        .padding(.vertical, 11)
        .background(glassFill)
        .overlay(glassStroke)
        .overlay(alignment: .top) { topHighlight }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 2)
        .opacity(isDisabled ? 0.45 : 1)
        .contentShape(Capsule())
    }

    /// 半透明玻璃填充：系统材质 + 一层自上而下变淡的白色。
    private var glassFill: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule().fill(
                    LinearGradient(
                        colors: [.white.opacity(0.24), .white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            )
    }

    /// 细白描边，顶部亮、底部暗，模拟玻璃厚度。
    private var glassStroke: some View {
        Capsule().strokeBorder(
            LinearGradient(
                colors: [.white.opacity(0.90), .white.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            ),
            lineWidth: 1
        )
    }

    /// 顶部高光线。
    private var topHighlight: some View {
        Capsule()
            .fill(.white.opacity(0.55))
            .frame(height: 1)
            .padding(.horizontal, 20)
            .padding(.top, 1)
    }
}

/// 前进/后退玻璃胶囊：左半后退、右半前进，中间细分隔线。
struct BackForwardControl: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(systemName: "chevron.left", enabled: canGoBack, action: onBack)
                .help(NSLocalizedString("后退", comment: ""))
            Rectangle()
                .fill(.white.opacity(0.22))
                .frame(width: 1, height: 16)
            item(systemName: "chevron.right", enabled: canGoForward, action: onForward)
                .help(NSLocalizedString("前进", comment: ""))
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule().fill(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                )
        )
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.85), .white.opacity(0.16)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func item(
        systemName: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.primary : Color.secondary.opacity(0.35))
        .disabled(!enabled)
    }
}
