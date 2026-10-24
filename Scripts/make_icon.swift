#!/usr/bin/env swift
// 生成 AZip 应用图标母版（1024x1024 PNG）。
// 用法：swift Scripts/make_icon.swift <输出路径>
import AppKit
import CoreGraphics
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

// MARK: - 背景

let plateInset: CGFloat = 100
let plate = CGRect(
    x: plateInset,
    y: plateInset,
    width: canvas - plateInset * 2,
    height: canvas - plateInset * 2
)
let plateRadius: CGFloat = 186
let platePath = CGPath(
    roundedRect: plate,
    cornerWidth: plateRadius,
    cornerHeight: plateRadius,
    transform: nil
)

context.saveGState()
context.addPath(platePath)
context.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 0.47, green: 0.66, blue: 1.00, alpha: 1),
        CGColor(red: 0.17, green: 0.22, blue: 0.80, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawLinearGradient(
    gradient,
    start: CGPoint(x: plate.midX, y: plate.maxY),
    end: CGPoint(x: plate.midX, y: plate.minY),
    options: []
)

// 顶部柔和高光
let highlight = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.22),
        CGColor(red: 1, green: 1, blue: 1, alpha: 0.0)
    ] as CFArray,
    locations: [0, 1]
)!
context.drawRadialGradient(
    highlight,
    startCenter: CGPoint(x: plate.midX, y: plate.maxY - 40),
    startRadius: 0,
    endCenter: CGPoint(x: plate.midX, y: plate.maxY - 40),
    endRadius: 520,
    options: []
)
context.restoreGState()

// MARK: - 底座（安装目标）

let tray = CGRect(x: 300, y: 232, width: 424, height: 60)
let trayPath = CGPath(
    roundedRect: tray,
    cornerWidth: 30,
    cornerHeight: 30,
    transform: nil
)
context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.92))
context.addPath(trayPath)
context.fillPath()

// MARK: - 向下箭头

let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: 462, y: 560))
arrow.addLine(to: CGPoint(x: 372, y: 560))
arrow.addLine(to: CGPoint(x: 512, y: 348))
arrow.addLine(to: CGPoint(x: 652, y: 560))
arrow.addLine(to: CGPoint(x: 562, y: 560))
arrow.addLine(to: CGPoint(x: 562, y: 800))
arrow.addArc(
    center: CGPoint(x: 512, y: 800),
    radius: 50,
    startAngle: 0,
    endAngle: .pi,
    clockwise: false
)
arrow.closeSubpath()

context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
context.addPath(arrow)
context.fillPath()

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
