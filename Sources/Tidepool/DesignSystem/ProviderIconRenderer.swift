import AppKit

/// Provider 品牌图标 + App 的 T 字标（菜单栏/设置/引导共用）。
@MainActor
enum ProviderIconRenderer {
    private static var cache: [String: NSImage] = [:]
    /// 官方 PNG logo 的像素尺寸与不透明内容包围盒缓存。
    private struct LogoMetrics {
        var imageSize: CGSize
        /// NSImage 坐标（原点左下），像素单位。
        var content: CGRect
    }
    private static var metricsCache: [String: LogoMetrics] = [:]

    /// 16–20pt 的 Provider 图标：彩色模式使用品牌色，单色模式使用模板。
    static func icon(for provider: ProviderID, colorMode: Bool, size: CGFloat) -> NSImage? {
        let key = "\(provider.rawValue)-\(colorMode)-\(size)"
        if let cached = cache[key] { return cached }

        // 云厂商使用官方彩色 logo（保留品牌色），单色模式再压成模板。
        // 按内容包围盒等比缩放：内容高度统一为画布的 75%，整图等比绘制，绝不变形。
        if let encoded = ProviderLogoData.base64(for: provider),
           let data = Data(base64Encoded: encoded),
           let logo = NSImage(data: data) {
            let metrics = logoMetrics(for: provider)
            let contentHeight = size * 0.75
            var scale = contentHeight / metrics.content.height
            if metrics.content.width * scale > size * 1.25 {
                scale = (size * 1.25) / metrics.content.width
            }
            let logoRect = NSRect(
                x: size / 2 - metrics.content.midX * scale,
                y: size / 2 - metrics.content.midY * scale,
                width: metrics.imageSize.width * scale,
                height: metrics.imageSize.height * scale
            )
            let image = raster(size: NSSize(width: size, height: size)) { rect in
                logo.draw(in: logoRect)
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
        let tintedImage = tinted(base, color: tint, size: size)
        let image = provider == .kimiCode
            ? withCodeBadge(tintedImage, colorMode: colorMode, size: size)
            : tintedImage
        image.isTemplate = !colorMode
        cache[key] = image
        return image
    }

    /// Kimi Code 与 Kimi 共用同一个螺旋 logo，右下角加一个 `</>` 角标区分。
    /// 彩色模式：白底 + 品牌色代码符号；单色模式：挖空螺旋再描代码符号，跟随菜单栏着色。
    private static func withCodeBadge(_ base: NSImage, colorMode: Bool, size: CGFloat) -> NSImage {
        raster(size: NSSize(width: size, height: size)) { rect in
            base.draw(in: rect)

            let diameter = size * 0.62
            let badge = NSRect(x: size - diameter, y: 0, width: diameter, height: diameter)

            if colorMode {
                NSColor.white.setFill()
                NSBezierPath(ovalIn: badge).fill()
            } else {
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSColor.black.setFill()
                NSBezierPath(ovalIn: badge).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
            }

            drawCodeGlyph(
                in: badge.insetBy(dx: diameter * 0.06, dy: diameter * 0.06),
                color: colorMode ? ProviderID.kimiCode.nsBrandColor : .black
            )
        }
    }

    private static func drawCodeGlyph(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()

        func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }

        path.move(to: point(0.30, 0.70))
        path.line(to: point(0.07, 0.50))
        path.line(to: point(0.30, 0.30))
        path.move(to: point(0.70, 0.70))
        path.line(to: point(0.93, 0.50))
        path.line(to: point(0.70, 0.30))
        path.move(to: point(0.56, 0.80))
        path.line(to: point(0.44, 0.20))
        path.lineWidth = max(0.8, rect.width * 0.12)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
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

    /// 官方 PNG logo 的不透明内容包围盒（NSImage 坐标，原点在左下）。
    /// 各品牌源图的留白比例不同，渲染时按这个包围盒归一内容高度。
    private static func logoMetrics(for provider: ProviderID) -> LogoMetrics {
        if let cached = metricsCache[provider.rawValue] { return cached }
        var metrics = LogoMetrics(imageSize: CGSize(width: 1, height: 1), content: CGRect(x: 0, y: 0, width: 1, height: 1))
        if let encoded = ProviderLogoData.base64(for: provider),
           let data = Data(base64Encoded: encoded),
           let rep = NSBitmapImageRep(data: data),
           let cg = rep.cgImage {
            let w = cg.width, h = cg.height
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(
                data: &pixels, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            if let ctx {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                var minX = w, maxX = -1, minY = h, maxY = -1
                for y in 0..<h {
                    for x in 0..<w where pixels[(y * w + x) * 4 + 3] > 4 {
                        minX = min(minX, x); maxX = max(maxX, x)
                        minY = min(minY, y); maxY = max(maxY, y)
                    }
                }
                if maxX >= minX, maxY >= minY {
                    // 位图内存第 0 行是图片顶部；NSImage 坐标原点在左下，需翻转
                    metrics = LogoMetrics(
                        imageSize: CGSize(width: w, height: h),
                        content: CGRect(
                            x: CGFloat(minX),
                            y: CGFloat(h - 1 - maxY),
                            width: CGFloat(maxX - minX + 1),
                            height: CGFloat(maxY - minY + 1)
                        )
                    )
                }
            }
        }
        metricsCache[provider.rawValue] = metrics
        return metrics
    }

    /// 单色剪影（指定颜色，非模板）：单色偏好下和彩色状态圆点合成时使用，
    /// 这样 logo 跟随外观明暗，而圆点保留真实颜色。
    static func silhouetteIcon(for provider: ProviderID, color: NSColor, size: CGFloat) -> NSImage? {
        let key = "silhouette-\(provider.rawValue)-\(color)-\(size)"
        if let cached = cache[key] { return cached }
        guard let base = icon(for: provider, colorMode: true, size: size) else { return nil }
        let image = raster(size: NSSize(width: size, height: size)) { rect in
            base.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceIn)
        }
        image.isTemplate = false
        cache[key] = image
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
