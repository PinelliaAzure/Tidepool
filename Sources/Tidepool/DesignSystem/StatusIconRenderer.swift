import AppKit

/// 程序化渲染的鲸鱼剪影（Template / 品牌色两种模式）。
/// 视觉基准：100 × 64 画布，鲸头朝右（朝向后面的金额文字）。
@MainActor
enum StatusIconRenderer {
    /// 菜单栏图标：Provider 品牌标识（或 App T 字标）+ 低余额 / 闲时角标。
    static func menuBarIcon(
        provider: ProviderID?,
        colorMode: Bool,
        dot: NSColor?,
        size: CGFloat = 18
    ) -> NSImage {
        let appearanceIsDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // 单色偏好：logo 固定白色（菜单栏通常为深色），圆点保留真实颜色
        let monoColor: NSColor = .white

        let image = NSImage(size: NSSize(width: size, height: size))
        // 圆点需要保留真实颜色，整张图不能是模板
        image.isTemplate = false
        image.lockFocus()
        defer { image.unlockFocus() }

        let markSize = size * 0.84
        let markRect = NSRect(x: 0, y: size * 0.08, width: markSize, height: markSize)
        if let provider {
            let mark = colorMode
                ? ProviderIconRenderer.icon(for: provider, colorMode: true, size: markSize)
                : ProviderIconRenderer.silhouetteIcon(for: provider, color: monoColor, size: markSize)
            if let mark {
                mark.draw(in: markRect)
            } else {
                ProviderIconRenderer.appMark(
                    size: markSize,
                    tint: colorMode ? provider.nsBrandColor : monoColor
                ).draw(in: markRect)
            }
        } else {
            ProviderIconRenderer.appMark(
                size: markSize,
                tint: colorMode ? ProviderID.deepseek.nsBrandColor : monoColor
            ).draw(in: markRect)
        }

        // 右下角圆点，全平台统一：峰时红 / 谷时绿 / 其他白
        if let dot {
            let dotSize = size * 0.26
            let rect = NSRect(x: size - dotSize, y: 0, width: dotSize, height: dotSize)
            let indicator = NSBezierPath(ovalIn: rect)
            dot.setFill()
            indicator.fill()
            // 白点在浅色菜单栏上需要细描边才看得见
            if dot == .white {
                (appearanceIsDark ? NSColor.black.withAlphaComponent(0.35) : NSColor.gray.withAlphaComponent(0.6)).setStroke()
                indicator.lineWidth = 0.7
                indicator.stroke()
            }
        }
        return image
    }

    /// 「全部」模式：每个 Provider 一个品牌 logo + 紧凑数值，中间用 · 分隔。
    /// 菜单栏空间有限，不放厂商文字名，logo 直接代表品牌。
    /// 每个 logo 右下角带状态圆点（峰时红 / 谷时绿 / 其他白，全平台统一）。
    static func allProvidersIcon(
        items: [AppStore.MenuBarItem],
        colorMode: Bool,
        height: CGFloat = 22
    ) -> NSImage {
        let logoSize: CGFloat = 15
        let gap: CGFloat = 5
        let appearanceIsDark = NSApp?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        // 单色偏好：logo 与文字固定白色，圆点保留真实颜色
        let monoColor: NSColor = .white
        let separatorColor = colorMode
            ? (appearanceIsDark ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.55))
            : NSColor.white.withAlphaComponent(0.55)
        let separatorAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .regular),
            .foregroundColor: separatorColor
        ]
        let separator = NSAttributedString(string: " · ", attributes: separatorAttributes)
        let separatorWidth = separator.size().width

        let segments: [(provider: ProviderID, logo: NSImage?, text: NSAttributedString, dot: NSColor)] = items.map { item in
            let logo = colorMode
                ? ProviderIconRenderer.icon(for: item.provider, colorMode: true, size: logoSize)
                : ProviderIconRenderer.silhouetteIcon(for: item.provider, color: monoColor, size: logoSize)
            let text = colorMode ? item.value : Self.monoText(item.value)
            return (item.provider, logo, text, item.dotColor)
        }

        var totalWidth: CGFloat = 0
        for (index, segment) in segments.enumerated() {
            if index > 0 { totalWidth += separatorWidth }
            totalWidth += logoSize + gap + segment.text.size().width
        }

        let width = ceil(totalWidth)
        let image = NSImage(size: NSSize(width: width, height: height))
        // 圆点保留真实颜色，合成图不能是模板
        image.isTemplate = false
        image.lockFocus()
        defer { image.unlockFocus() }

        var x: CGFloat = 0
        for (index, segment) in segments.enumerated() {
            if index > 0 {
                separator.draw(at: NSPoint(x: x, y: (height - separator.size().height) / 2))
                x += separatorWidth
            }
            let logoOriginY = (height - logoSize) / 2
            if let logo = segment.logo {
                logo.draw(in: NSRect(x: x, y: logoOriginY, width: logoSize, height: logoSize))
            } else {
                // 没有品牌图的渠道（如自定义）：品牌色圆点代表
                let dotSize = logoSize * 0.62
                let dot = NSBezierPath(
                    ovalIn: NSRect(x: x + (logoSize - dotSize) / 2, y: (height - dotSize) / 2, width: dotSize, height: dotSize)
                )
                (colorMode ? segment.provider.nsBrandColor : monoColor).setFill()
                dot.fill()
            }
            let dotSize = logoSize * 0.34
            let rect = NSRect(x: x + logoSize - dotSize, y: logoOriginY, width: dotSize, height: dotSize)
            let indicator = NSBezierPath(ovalIn: rect)
            segment.dot.setFill()
            indicator.fill()
            if segment.dot == .white {
                (appearanceIsDark ? NSColor.black.withAlphaComponent(0.35) : NSColor.gray.withAlphaComponent(0.6)).setStroke()
                indicator.lineWidth = 0.6
                indicator.stroke()
            }
            x += logoSize + gap
            let textSize = segment.text.size()
            segment.text.draw(at: NSPoint(x: x, y: (height - textSize.height) / 2))
            x += textSize.width
        }

        return image
    }

    /// 单色模式：基础文字转白，黄色/红色状态色保留（菜单栏为深色）。
    private static func monoText(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let range = NSRange(location: 0, length: result.length)
        result.enumerateAttribute(.foregroundColor, in: range) { value, subrange, _ in
            if let color = value as? NSColor, color == .systemYellow || color == .systemRed {
                return
            }
            result.addAttribute(.foregroundColor, value: NSColor.white, range: subrange)
        }
        return result
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
