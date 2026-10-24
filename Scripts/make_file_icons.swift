#!/usr/bin/env swift
// 渲染归档类文件图标为 PNG（供 iconutil 打包成 .icns）。
// 用法：swift Scripts/make_file_icons.swift <输出目录>
import AppKit
import SwiftUI

// MARK: - 设计参数（与 App 内 FileTypeIcon 保持一致）

struct IconStyle {
    let key: String
    let abbreviation: String
    let hex: UInt32
    let isDisc: Bool
}

let styles: [IconStyle] = [
    IconStyle(key: "7z", abbreviation: "7Z", hex: 0xB5652A, isDisc: false),
    IconStyle(key: "rar", abbreviation: "RAR", hex: 0x9A4E2A, isDisc: false),
    IconStyle(key: "zip", abbreviation: "ZIP", hex: 0xF08A2C, isDisc: false),
    IconStyle(key: "tar", abbreviation: "TAR", hex: 0xE8A33D, isDisc: false),
    IconStyle(key: "zst", abbreviation: "ZST", hex: 0xD96A3A, isDisc: false),
    IconStyle(key: "gz", abbreviation: "GZ", hex: 0xC97B3C, isDisc: false),
    IconStyle(key: "bz2", abbreviation: "BZ2", hex: 0xE8823A, isDisc: false),
    IconStyle(key: "xz", abbreviation: "XZ", hex: 0xDDA23C, isDisc: false),
    IconStyle(key: "lz", abbreviation: "LZ", hex: 0xA85A28, isDisc: false),
    IconStyle(key: "lz4", abbreviation: "LZ4", hex: 0xD9924A, isDisc: false),
    IconStyle(key: "br", abbreviation: "BR", hex: 0xE2772E, isDisc: false),
    IconStyle(key: "lrz", abbreviation: "LRZ", hex: 0x9C5424, isDisc: false),
    IconStyle(key: "aar", abbreviation: "AAR", hex: 0xB0602C, isDisc: false),
    IconStyle(key: "sn", abbreviation: "SN", hex: 0xC9A24A, isDisc: false),
    IconStyle(key: "wim", abbreviation: "WIM", hex: 0xB06A32, isDisc: false),
    IconStyle(key: "dmg", abbreviation: "DMG", hex: 0x4A4E57, isDisc: true),
    IconStyle(key: "iso", abbreviation: "ISO", hex: 0x6A707A, isDisc: true),
]

func color(_ hex: UInt32) -> Color {
    Color(
        .sRGB,
        red: Double((hex >> 16) & 0xFF) / 255,
        green: Double((hex >> 8) & 0xFF) / 255,
        blue: Double(hex & 0xFF) / 255,
        opacity: 1
    )
}

struct IconArt: View {
    let style: IconStyle

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let fold = width * 0.28

            ZStack {
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
                        colors: [color(style.hex).opacity(0.92), color(style.hex)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                Path { path in
                    path.move(to: CGPoint(x: width - fold, y: 0))
                    path.addLine(to: CGPoint(x: width, y: fold))
                    path.addLine(to: CGPoint(x: width - fold, y: fold))
                    path.closeSubpath()
                }
                .fill(Color.white.opacity(0.38))

                if style.isDisc {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.55), lineWidth: width * 0.05)
                            .frame(width: width * 0.52, height: width * 0.52)
                        Circle()
                            .fill(Color.white.opacity(0.28))
                            .frame(width: width * 0.14, height: width * 0.14)
                    }
                    .position(x: width * 0.5, y: height * 0.42)
                } else {
                    VStack(spacing: width * 0.075) {
                        ForEach(0..<4, id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: width * 0.075, height: width * 0.075)
                        }
                    }
                    .position(x: width * 0.2, y: height * 0.42)
                }

                Text(style.abbreviation)
                    .font(.system(size: width * 0.21, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.96))
                    .position(x: width * 0.5, y: height * 0.76)
            }
            .clipShape(RoundedRectangle(cornerRadius: width * 0.08, style: .continuous))
        }
    }
}

// MARK: - 渲染

guard CommandLine.arguments.count > 1 else {
    print("usage: make_file_icons.swift <output-dir>")
    exit(1)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

let canvas: CGFloat = 1024
let padding: CGFloat = 100
let artSize = canvas - padding * 2

MainActor.assumeIsolated {
for style in styles {
    let view = IconArt(style: style)
        .frame(width: artSize * 0.78, height: artSize)
        .padding(padding)
        .frame(width: canvas, height: canvas)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("failed: \(style.key)")
        continue
    }
    let url = outputDirectory.appendingPathComponent("\(style.key).png")
    try? png.write(to: url)
    print("wrote \(url.lastPathComponent)")
}
}
