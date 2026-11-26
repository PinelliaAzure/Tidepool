#!/usr/bin/env swift
import AppKit

// 生成 Tidepool 的 1024×1024 应用图标：深蓝渐变 + T 字标 + 三个 Provider 点。
// 输出：Resources/icon-1024.png

let canvas: CGFloat = 1024
let image = NSImage(size: NSSize(width: canvas, height: canvas))
image.lockFocus()

let inset: CGFloat = 86
let rect = NSRect(x: inset, y: inset, width: canvas - inset * 2, height: canvas - inset * 2)
let radius = rect.width * 0.225
let shape = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

NSGraphicsContext.current?.saveGraphicsState()
shape.addClip()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0x5B / 255.0, green: 0x78 / 255.0, blue: 0xFF / 255.0, alpha: 1),
    NSColor(srgbRed: 0x2C / 255.0, green: 0x47 / 255.0, blue: 0xC9 / 255.0, alpha: 1),
    NSColor(srgbRed: 0x11 / 255.0, green: 0x1F / 255.0, blue: 0x4E / 255.0, alpha: 1)
])
gradient?.draw(in: rect, angle: -62)

// T 字标
NSColor.white.setFill()
let bar = NSBezierPath(
    roundedRect: NSRect(x: 322, y: 566, width: 380, height: 118),
    xRadius: 59,
    yRadius: 59
)
bar.fill()

let stem = NSBezierPath(
    roundedRect: NSRect(x: 452, y: 356, width: 120, height: 250),
    xRadius: 60,
    yRadius: 60
)
stem.fill()

// 三个 Provider 点
let colors = [
    NSColor(srgbRed: 0x6E / 255.0, green: 0x8B / 255.0, blue: 0xFF / 255.0, alpha: 1),
    NSColor(srgbRed: 0xA7 / 255.0, green: 0x8B / 255.0, blue: 0xFA / 255.0, alpha: 1),
    NSColor(srgbRed: 0x2D / 255.0, green: 0xD4 / 255.0, blue: 0xBF / 255.0, alpha: 1)
]
for (index, color) in colors.enumerated() {
    color.setFill()
    let dot = NSRect(x: 402 + CGFloat(index) * 78, y: 286, width: 44, height: 44)
    NSBezierPath(ovalIn: dot).fill()
}

NSGraphicsContext.current?.restoreGraphicsState()

// 内圈高光
shape.lineWidth = 3
NSColor.white.withAlphaComponent(0.16).setStroke()
shape.stroke()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("无法生成图标")
}

let directory = URL(fileURLWithPath: "Resources", isDirectory: true)
try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let output = directory.appendingPathComponent("icon-1024.png")
try png.write(to: output)
print("wrote \(output.path)")
