import AZipCore
import SwiftUI

struct BottomBar: View {
    @ObservedObject var model: DMGSessionModel

    private var isDisabled: Bool {
        model.rootApplications.isEmpty || model.isInstalling
    }

    var body: some View {
        VStack(spacing: 6) {
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
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .padding(.bottom, 18)
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

    private var statusText: String {
        let count = model.rootApplications.count
        switch count {
        case 0:
            return NSLocalizedString("此磁盘映像没有可安装的应用程序", comment: "")
        case 1:
            return String(
                format: NSLocalizedString("可安装：%@", comment: ""),
                model.rootApplications[0].name
            )
        default:
            return String(
                format: NSLocalizedString("%d 个应用程序可安装", comment: ""),
                count
            )
        }
    }
}
