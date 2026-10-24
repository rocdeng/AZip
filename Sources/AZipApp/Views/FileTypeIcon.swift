import SwiftUI

/// 关联文件类型的图标规格（与设计稿一致：折角纸张 + 琥珀橙系 + 缩写）。
struct FileTypeIconStyle: Sendable {
    /// 官方导出图标的资源名（大写格式名）。
    let key: String
    let abbreviation: String
    let color: Color
    let isDisc: Bool

    init(_ key: String, _ abbreviation: String, _ hex: UInt32, isDisc: Bool = false) {
        self.key = key
        self.abbreviation = abbreviation
        self.color = Color(hex: hex)
        self.isDisc = isDisc
    }

    /// 按扩展名取图标样式；不认识的格式返回 nil（回退系统图标）。
    static func style(forExtension ext: String) -> FileTypeIconStyle? {
        switch ext.lowercased() {
        case "7z":   return FileTypeIconStyle("7Z", "7Z", 0xB5652A)
        case "rar":  return FileTypeIconStyle("RAR", "RAR", 0x9A4E2A)
        case "zip":  return FileTypeIconStyle("ZIP", "ZIP", 0xF08A2C)
        case "apk":  return FileTypeIconStyle("APK", "APK", 0x3D8B4F)
        case "tar":  return FileTypeIconStyle("TAR", "TAR", 0xE8A33D)
        case "zst":  return FileTypeIconStyle("ZSTD", "ZST", 0xD96A3A)
        case "gz":   return FileTypeIconStyle("GZIP", "GZ", 0xC97B3C)
        case "tgz":  return FileTypeIconStyle("GZIP", "TGZ", 0xC97B3C)
        case "bz2":  return FileTypeIconStyle("BZIP2", "BZ2", 0xE8823A)
        case "tbz", "tbz2": return FileTypeIconStyle("BZIP2", "TBZ", 0xE8823A)
        case "xz":   return FileTypeIconStyle("XZ", "XZ", 0xDDA23C)
        case "txz":  return FileTypeIconStyle("XZ", "TXZ", 0xDDA23C)
        case "lz":   return FileTypeIconStyle("LZIP", "LZ", 0xA85A28)
        case "lz4":  return FileTypeIconStyle("LZ4", "LZ4", 0xD9924A)
        case "br":   return FileTypeIconStyle("BROTLI", "BR", 0xE2772E)
        case "lrz":  return FileTypeIconStyle("LRZIP", "LRZ", 0x9C5424)
        case "aar":  return FileTypeIconStyle("AAR", "AAR", 0xB0602C)
        case "sz":   return FileTypeIconStyle("SNAPPY", "SN", 0xC9A24A)
        case "wim":  return FileTypeIconStyle("WIM", "WIM", 0xB06A32)
        case "dmg":  return FileTypeIconStyle("DMG", "DMG", 0x4A4E57, isDisc: true)
        case "iso":  return FileTypeIconStyle("ISO", "ISO", 0x6A707A, isDisc: true)
        default:     return nil
        }
    }
}

/// 折角文件图标：右上角折角、左侧白点、底部格式缩写；镜像类改成光盘圆环。
struct FileTypeIcon: View {
    let style: FileTypeIconStyle

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let fold = width * 0.28

            ZStack {
                // 纸张主体（右上角切角）
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: width - fold, y: 0))
                    path.addLine(to: CGPoint(x: width, y: fold))
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [style.color.opacity(0.92), style.color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // 折角三角
                Path { path in
                    path.move(to: CGPoint(x: width - fold, y: 0))
                    path.addLine(to: CGPoint(x: width, y: fold))
                    path.addLine(to: CGPoint(x: width - fold, y: fold))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.38))

                if style.isDisc {
                    discMark(width: width, height: height)
                } else {
                    dotsMark(width: width, height: height)
                }

                Text(style.abbreviation)
                    .font(.system(size: width * 0.21, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.15), radius: 0.5, y: 0.5)
                    .position(x: width * 0.5, y: height * 0.76)
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.08, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: width * 0.04, y: width * 0.02)
        }
        .aspectRatio(0.78, contentMode: .fit)
    }

    /// 压缩类：左侧一列白色圆点。
    private func dotsMark(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: width * 0.075) {
            ForEach(0..<4, id: \.self) { _ in
                Circle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: width * 0.075, height: width * 0.075)
            }
        }
        .position(x: width * 0.2, y: height * 0.42)
    }

    /// 镜像类：正面光盘圆环。
    private func discMark(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.55), lineWidth: width * 0.05)
                .frame(width: width * 0.52, height: width * 0.52)
            Circle()
                .fill(Color.white.opacity(0.28))
                .frame(width: width * 0.14, height: width * 0.14)
        }
        .position(x: width * 0.5, y: height * 0.42)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
