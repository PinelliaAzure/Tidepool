import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(nsColor: NSColor(hex: hex))
    }
}

// MARK: - 玻璃卡片

/// 面板底由 NSPopover 提供系统玻璃材质；卡片只做半透明填充 + 高光描边，
/// 避免多层模糊叠加导致的"糊"。
struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        return content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(dark ? 0.09 : 0.52))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(dark ? 0.20 : 0.85),
                                Color.primary.opacity(dark ? 0.10 : 0.08)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.9
                    )
            )
            .shadow(
                color: Color.black.opacity(dark ? 0.18 : 0.07),
                radius: 12,
                y: 4
            )
    }
}

/// NSPopover 的 vibrancy 会让 `.tertiary` 在深色模式下变暗到几乎看不见，
/// 这里用 primary 的透明度代替，深色/浅色都保持可读。
private struct TertiaryTextModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content.foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.48 : 0.42))
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }

    func tertiaryText() -> some View {
        modifier(TertiaryTextModifier())
    }

    /// 分区标题：小号加粗 + 次要色。
    func sectionHeader() -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
