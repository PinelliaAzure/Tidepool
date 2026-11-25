#!/usr/bin/env swift
import AppKit

// 生成 Tidepool 的 1024×1024 应用图标（深蓝渐变 + 白色鲸鱼 + 潮汐线）。
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

// 潮汐线
for (index, alpha) in [0.10, 0.07, 0.045].enumerated() {
    let y = rect.minY + 172 + CGFloat(index) * 58
    let wave = NSBezierPath()
    wave.move(to: NSPoint(x: rect.minX - 40, y: y))
    wave.curve(
        to: NSPoint(x: rect.maxX + 40, y: y + 26),
        controlPoint1: NSPoint(x: rect.midX - 240, y: y + 96),
        controlPoint2: NSPoint(x: rect.midX + 240, y: y - 46)
    )
    wave.lineWidth = 16
    NSColor.white.withAlphaComponent(alpha).setStroke()
    wave.stroke()
}

// 鲸鱼
let whaleWidth: CGFloat = 600
let whaleHeight = whaleWidth * 0.64
let whaleRect = NSRect(
    x: rect.midX - whaleWidth / 2,
    y: rect.midY - whaleHeight / 2 + 40,
    width: whaleWidth,
    height: whaleHeight
)

let path = NSBezierPath()
path.windingRule = .evenOdd
path.move(to: NSPoint(x: 92, y: 34))
path.curve(to: NSPoint(x: 58, y: 7), controlPoint1: NSPoint(x: 88, y: 16), controlPoint2: NSPoint(x: 74, y: 5))
path.curve(to: NSPoint(x: 28, y: 12), controlPoint1: NSPoint(x: 45, y: 8), controlPoint2: NSPoint(x: 36, y: 9))
path.curve(to: NSPoint(x: 21, y: 20), controlPoint1: NSPoint(x: 25, y: 13), controlPoint2: NSPoint(x: 22, y: 16))
path.curve(to: NSPoint(x: 7, y: 6), controlPoint1: NSPoint(x: 17, y: 14), controlPoint2: NSPoint(x: 12, y: 8))
path.curve(to: NSPoint(x: 24, y: 27), controlPoint1: NSPoint(x: 10, y: 15), controlPoint2: NSPoint(x: 17, y: 24))
path.curve(to: NSPoint(x: 6, y: 46), controlPoint1: NSPoint(x: 13, y: 33), controlPoint2: NSPoint(x: 8, y: 40))
path.curve(to: NSPoint(x: 27, y: 34), controlPoint1: NSPoint(x: 13, y: 42), controlPoint2: NSPoint(x: 19, y: 37))
path.curve(to: NSPoint(x: 92, y: 34), controlPoint1: NSPoint(x: 48, y: 52), controlPoint2: NSPoint(x: 74, y: 52))
path.close()
path.append(NSBezierPath(ovalIn: NSRect(x: 69, y: 24, width: 5.5, height: 5.5)))

let transform = AffineTransform(
    m11: whaleRect.width / 100,
    m12: 0,
    m21: 0,
    m22: whaleRect.height / 64,
    tX: whaleRect.minX,
    tY: whaleRect.minY
)
path.transform(using: transform)
NSColor.white.setFill()
path.fill()

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
