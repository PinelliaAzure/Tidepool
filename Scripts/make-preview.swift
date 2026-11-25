#!/usr/bin/env swift
import AppKit

// 把 `--preview` 截下来的面板 PNG 放到统一的深色渐变背景上，生成 README 效果图。
// 用法：swift Scripts/make-preview.swift <panel.png> <out.png>

let args = CommandLine.arguments
guard args.count >= 3, let panel = NSImage(contentsOfFile: args[1]) else {
    FileHandle.standardError.write(Data("usage: make-preview.swift <panel.png> <out.png>\n".utf8))
    exit(1)
}

let panelSize = panel.size
let margin: CGFloat = 44
let size = NSSize(width: panelSize.width + margin * 2, height: panelSize.height + margin * 2)

let canvas = NSImage(size: size)
canvas.lockFocus()

let gradient = NSGradient(colors: [
    NSColor(srgbRed: 0x17 / 255.0, green: 0x25 / 255.0, blue: 0x3D / 255.0, alpha: 1),
    NSColor(srgbRed: 0x2A / 255.0, green: 0x44 / 255.0, blue: 0x68 / 255.0, alpha: 1),
    NSColor(srgbRed: 0x0C / 255.0, green: 0x12 / 255.0, blue: 0x1C / 255.0, alpha: 1)
])
gradient?.draw(in: NSRect(origin: .zero, size: size), angle: -36)

panel.draw(in: NSRect(x: margin, y: margin, width: panelSize.width, height: panelSize.height))

canvas.unlockFocus()

guard let tiff = canvas.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    exit(1)
}
try png.write(to: URL(fileURLWithPath: args[2]))
print("wrote \(args[2])")
