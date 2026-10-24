#!/usr/bin/env swift
// 生成 AZip 应用图标母版（1024x1024 PNG）。
// 用法：swift Scripts/make_icon.swift <输出路径>
import AppKit
import CoreGraphics
import CoreText
import Foundation

let canvas: CGFloat = 1024
let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "AppIcon-1024.png"

guard let context = CGContext(
    data: nil,
    width: Int(canvas),
    height: Int(canvas),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("无法创建绘图上下文")
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func fill(_ path: CGPath, with color: CGColor) {
    context.setFillColor(color)
    context.addPath(path)
    context.fillPath()
}

func gradient(
    _ path: CGPath,
    from: CGColor,
    to: CGColor,
    start: CGPoint,
    end: CGPoint
) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let g = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [from, to] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(g, start: start, end: end, options: [])
    context.restoreGState()
}

// MARK: - 底板

let plateInset: CGFloat = 96
let plate = CGRect(
    x: plateInset,
    y: plateInset,
    width: canvas - plateInset * 2,
    height: canvas - plateInset * 2
)
let platePath = CGPath(
    roundedRect: plate,
    cornerWidth: 186,
    cornerHeight: 186,
    transform: nil
)
gradient(
    platePath,
    from: color(247, 242, 233),
    to: color(232, 224, 211),
    start: CGPoint(x: plate.midX, y: plate.maxY),
    end: CGPoint(x: plate.midX, y: plate.minY)
)

// MARK: - 箱子

let boxTop: CGFloat = 452
let boxBottom: CGFloat = 226
let boxLeft: CGFloat = 322
let boxRight: CGFloat = 702

// 后侧翻盖（先画，被箱体压住一部分）
let backFlap = CGMutablePath()
backFlap.move(to: CGPoint(x: boxLeft + 30, y: boxTop + 6))
backFlap.addLine(to: CGPoint(x: boxRight - 30, y: boxTop + 6))
backFlap.addLine(to: CGPoint(x: boxRight - 92, y: boxTop + 92))
backFlap.addLine(to: CGPoint(x: boxLeft + 92, y: boxTop + 92))
backFlap.closeSubpath()
gradient(
    backFlap,
    from: color(214, 122, 37),
    to: color(190, 102, 26),
    start: CGPoint(x: 512, y: boxTop + 92),
    end: CGPoint(x: 512, y: boxTop)
)

// MARK: - 向上箭头（在箱体之前画，底部会被箱体遮住）

let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 486, y: boxTop - 40))
arrow.addLine(to: CGPoint(x: 486, y: 690))
arrow.addLine(to: CGPoint(x: 408, y: 690))
arrow.addLine(to: CGPoint(x: 512, y: 826))
arrow.addLine(to: CGPoint(x: 616, y: 690))
arrow.addLine(to: CGPoint(x: 538, y: 690))
arrow.addLine(to: CGPoint(x: 538, y: boxTop - 40))
arrow.closeSubpath()

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: color(120, 70, 20, 0.28))
gradient(
    arrow,
    from: color(255, 255, 255),
    to: color(243, 237, 226),
    start: CGPoint(x: 512, y: 826),
    end: CGPoint(x: 512, y: boxTop)
)
context.restoreGState()

// MARK: - 箱内

let inner = CGMutablePath()
inner.move(to: CGPoint(x: boxLeft, y: boxTop))
inner.addLine(to: CGPoint(x: boxRight, y: boxTop))
inner.addLine(to: CGPoint(x: boxRight - 42, y: boxTop - 52))
inner.addLine(to: CGPoint(x: boxLeft + 42, y: boxTop - 52))
inner.closeSubpath()
gradient(
    inner,
    from: color(176, 88, 20),
    to: color(140, 66, 14),
    start: CGPoint(x: 512, y: boxTop),
    end: CGPoint(x: 512, y: boxTop - 52)
)

// MARK: - 箱体正面

let front = CGMutablePath()
front.move(to: CGPoint(x: boxLeft, y: boxTop - 40))
front.addLine(to: CGPoint(x: boxRight, y: boxTop - 40))
front.addLine(to: CGPoint(x: boxRight - 14, y: boxBottom))
front.addLine(to: CGPoint(x: boxLeft + 14, y: boxBottom))
front.closeSubpath()
gradient(
    front,
    from: color(243, 160, 71),
    to: color(214, 118, 32),
    start: CGPoint(x: 512, y: boxTop),
    end: CGPoint(x: 512, y: boxBottom)
)

// MARK: - 左右外翻盖

let leftFlap = CGMutablePath()
leftFlap.move(to: CGPoint(x: boxLeft + 4, y: boxTop - 30))
leftFlap.addLine(to: CGPoint(x: boxLeft + 4, y: boxTop + 12))
leftFlap.addLine(to: CGPoint(x: boxLeft - 108, y: boxTop + 74))
leftFlap.addLine(to: CGPoint(x: boxLeft - 116, y: boxTop + 32))
leftFlap.closeSubpath()
gradient(
    leftFlap,
    from: color(248, 176, 92),
    to: color(226, 138, 48),
    start: CGPoint(x: boxLeft, y: boxTop + 74),
    end: CGPoint(x: boxLeft, y: boxTop - 30)
)

let rightFlap = CGMutablePath()
rightFlap.move(to: CGPoint(x: boxRight - 4, y: boxTop - 30))
rightFlap.addLine(to: CGPoint(x: boxRight - 4, y: boxTop + 12))
rightFlap.addLine(to: CGPoint(x: boxRight + 108, y: boxTop + 74))
rightFlap.addLine(to: CGPoint(x: boxRight + 116, y: boxTop + 32))
rightFlap.closeSubpath()
gradient(
    rightFlap,
    from: color(240, 160, 76),
    to: color(214, 124, 38),
    start: CGPoint(x: boxRight, y: boxTop + 74),
    end: CGPoint(x: boxRight, y: boxTop - 30)
)

// MARK: - 正面圆形徽章与字母 A

let badge = CGRect(x: 512 - 62, y: 300 - 62, width: 124, height: 124)
let badgePath = CGPath(ellipseIn: badge, transform: nil)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: color(120, 60, 10, 0.30))
fill(badgePath, with: color(255, 255, 255))
context.restoreGState()

let font = CTFontCreateWithName("Helvetica-Bold" as CFString, 82, nil)
let attributes: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor(srgbRed: 74 / 255, green: 44 / 255, blue: 24 / 255, alpha: 1)
]
let letter = NSAttributedString(string: "A", attributes: attributes)
let line = CTLineCreateWithAttributedString(letter)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
context.textPosition = CGPoint(
    x: badge.midX - bounds.width / 2 - bounds.minX,
    y: badge.midY - bounds.height / 2 - bounds.minY
)
CTLineDraw(line, context)

// MARK: - 输出

guard let image = context.makeImage() else {
    fatalError("无法生成位图")
}
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: canvas, height: canvas)
guard let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法编码 PNG")
}
try png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
