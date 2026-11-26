import AppKit

/// Provider 品牌图标 + App 的 T 字标（菜单栏/设置/引导共用）。
@MainActor
enum ProviderIconRenderer {
    private static var cache: [String: NSImage] = [:]

    /// 16–20pt 的 Provider 图标：彩色模式使用品牌色，单色模式使用模板。
    static func icon(for provider: ProviderID, colorMode: Bool, size: CGFloat) -> NSImage? {
        let key = "\(provider.rawValue)-\(colorMode)-\(size)"
        if let cached = cache[key] { return cached }

        // 云厂商使用官方彩色 logo（保留品牌色），单色模式再压成模板
        if let encoded = ProviderLogoData.base64(for: provider),
           let data = Data(base64Encoded: encoded),
           let logo = NSImage(data: data) {
            let image = raster(size: NSSize(width: size, height: size)) { rect in
                logo.draw(in: rect)
                if !colorMode {
                    NSColor.black.setFill()
                    rect.fill(using: .sourceIn)
                }
            }
            image.isTemplate = !colorMode
            cache[key] = image
            return image
        }

        guard let svg = ProviderArtwork.svg(for: provider),
              let data = svg.data(using: .utf8),
              let base = NSImage(data: data) else { return nil }

        let tint = colorMode ? provider.nsBrandColor : NSColor.black
        let image = tinted(base, color: tint, size: size)
        image.isTemplate = !colorMode
        cache[key] = image
        return image
    }

    /// Tidepool 的 App 标记：T + 三个 Provider 点。
    static func appMark(size: CGFloat, tint: NSColor? = nil) -> NSImage {
        let color = tint ?? .black
        let image = raster(size: NSSize(width: size, height: size)) { _ in
            let s = size / 18
            color.setFill()
            NSBezierPath(
                roundedRect: NSRect(x: 3.0 * s, y: 10.6 * s, width: 12.0 * s, height: 3.4 * s),
                xRadius: 1.7 * s,
                yRadius: 1.7 * s
            ).fill()
            NSBezierPath(
                roundedRect: NSRect(x: 7.1 * s, y: 5.4 * s, width: 3.8 * s, height: 6.6 * s),
                xRadius: 1.9 * s,
                yRadius: 1.9 * s
            ).fill()
            for index in 0..<3 {
                let rect = NSRect(
                    x: (5.0 + CGFloat(index) * 3.1) * s - 1.2 * s,
                    y: 2.0 * s - 1.2 * s,
                    width: 2.4 * s,
                    height: 2.4 * s
                )
                NSBezierPath(ovalIn: rect).fill()
            }
        }
        image.isTemplate = tint == nil
        return image
    }

    // MARK: - 绘制工具

    private static func tinted(_ base: NSImage, color: NSColor, size: CGFloat) -> NSImage {
        raster(size: NSSize(width: size, height: size)) { _ in
            base.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
            color.setFill()
            NSRect(x: 0, y: 0, width: size, height: size).fill(using: .sourceIn)
        }
    }

    private static func raster(size: NSSize, draw: (NSRect) -> Void) -> NSImage {
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale),
            pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        draw(NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
