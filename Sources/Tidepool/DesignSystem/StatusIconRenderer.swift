import AppKit

/// 程序化渲染的鲸鱼剪影（Template / 品牌色两种模式）。
/// 视觉基准：100 × 64 画布，鲸头朝右（朝向后面的金额文字）。
@MainActor
enum StatusIconRenderer {
    /// 菜单栏图标：Provider 品牌标识（或 App T 字标）+ 低余额 / 闲时角标。
    static func menuBarIcon(
        provider: ProviderID?,
        colorMode: Bool,
        alert: Bool,
        offPeak: Bool,
        size: CGFloat = 18
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.isTemplate = !colorMode
        image.lockFocus()
        defer { image.unlockFocus() }

        let markSize = size * 0.84
        let markRect = NSRect(x: 0, y: size * 0.08, width: markSize, height: markSize)
        if let provider,
           let mark = ProviderIconRenderer.icon(for: provider, colorMode: colorMode, size: markSize) {
            mark.draw(in: markRect)
        } else {
            ProviderIconRenderer.appMark(
                size: markSize,
                tint: colorMode ? ProviderID.deepseek.nsBrandColor : nil
            ).draw(in: markRect)
        }

        if offPeak {
            drawMoon(size: size, color: colorMode ? .systemTeal : .black)
        }

        if alert {
            let dotSize = size * 0.26
            let dot = NSBezierPath(
                ovalIn: NSRect(x: size - dotSize, y: 0, width: dotSize, height: dotSize)
            )
            (colorMode ? NSColor.systemRed : NSColor.black).setFill()
            dot.fill()
        }
        return image
    }

    /// 右上角的小月牙：闲时（非高峰）计价。
    private static func drawMoon(size: CGFloat, color: NSColor) {
        let radius = size * 0.165
        let center = NSPoint(x: size * 0.795, y: size * 0.795)
        let outer = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            )
        )
        let innerRadius = radius * 0.94
        let inner = NSBezierPath(
            ovalIn: NSRect(
                x: center.x - innerRadius + radius * 0.62,
                y: center.y - innerRadius + radius * 0.26,
                width: innerRadius * 2,
                height: innerRadius * 2
            )
        )
        let crescent = NSBezierPath()
        crescent.windingRule = .evenOdd
        crescent.append(outer)
        crescent.append(inner)
        color.setFill()
        crescent.fill()
    }

    /// 大尺寸鲸鱼（空态插画等）。
    static func whaleIcon(size: CGFloat, tint: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size * 0.7))
        image.isTemplate = false
        image.lockFocus()
        defer { image.unlockFocus() }
        drawWhale(in: NSRect(x: 0, y: 0, width: size, height: size * 0.7), color: tint)
        return image
    }

    private static func drawWhale(in rect: NSRect, color: NSColor) {
        let path = NSBezierPath()
        path.windingRule = .evenOdd

        // 身体：从右侧鼻尖起笔，沿头顶、背部到尾柄
        path.move(to: NSPoint(x: 92, y: 34))
        path.curve(
            to: NSPoint(x: 58, y: 7),
            controlPoint1: NSPoint(x: 88, y: 16),
            controlPoint2: NSPoint(x: 74, y: 5)
        )
        path.curve(
            to: NSPoint(x: 28, y: 12),
            controlPoint1: NSPoint(x: 45, y: 8),
            controlPoint2: NSPoint(x: 36, y: 9)
        )
        path.curve(
            to: NSPoint(x: 21, y: 20),
            controlPoint1: NSPoint(x: 25, y: 13),
            controlPoint2: NSPoint(x: 22, y: 16)
        )
        // 上尾鳍
        path.curve(
            to: NSPoint(x: 7, y: 6),
            controlPoint1: NSPoint(x: 17, y: 14),
            controlPoint2: NSPoint(x: 12, y: 8)
        )
        path.curve(
            to: NSPoint(x: 24, y: 27),
            controlPoint1: NSPoint(x: 10, y: 15),
            controlPoint2: NSPoint(x: 17, y: 24)
        )
        // 下尾鳍
        path.curve(
            to: NSPoint(x: 6, y: 46),
            controlPoint1: NSPoint(x: 13, y: 33),
            controlPoint2: NSPoint(x: 8, y: 40)
        )
        path.curve(
            to: NSPoint(x: 27, y: 34),
            controlPoint1: NSPoint(x: 13, y: 42),
            controlPoint2: NSPoint(x: 19, y: 37)
        )
        // 腹部回到鼻尖
        path.curve(
            to: NSPoint(x: 92, y: 34),
            controlPoint1: NSPoint(x: 48, y: 52),
            controlPoint2: NSPoint(x: 74, y: 52)
        )
        path.close()

        // 眼睛（镂空）
        let eye = NSBezierPath(ovalIn: NSRect(x: 69, y: 24, width: 5.5, height: 5.5))
        path.append(eye)

        let transform = AffineTransform(
            m11: rect.width / 100,
            m12: 0,
            m21: 0,
            m22: rect.height / 64,
            tX: rect.minX,
            tY: rect.minY
        )
        path.transform(using: transform)

        color.setFill()
        path.fill()
    }
}
