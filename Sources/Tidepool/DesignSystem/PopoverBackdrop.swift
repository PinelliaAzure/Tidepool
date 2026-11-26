import SwiftUI

/// 彩色毛玻璃背景：以当前 Provider 品牌色为主的柔光色块 + 磨砂层。
/// 色块饱和度足够高，保证「有颜色」；上层的材质与白色薄雾把对比度拉回来，
/// 这样即使壁纸花花绿绿，面板里的文字仍然清楚。
struct PopoverBackdrop: View {
    let accent: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let dark = colorScheme == .dark

            ZStack {
                base(dark: dark)

                blob(
                    accent,
                    opacity: dark ? 0.66 : 0.62,
                    diameter: width * 1.30,
                    x: -width * 0.30,
                    y: -height * 0.32,
                    blur: 86
                )
                blob(
                    Color(hex: 0x8B5CF6),
                    opacity: dark ? 0.52 : 0.50,
                    diameter: width * 1.10,
                    x: width * 0.56,
                    y: height * 0.04,
                    blur: 82
                )
                blob(
                    Color(hex: 0x14B8A6),
                    opacity: dark ? 0.44 : 0.46,
                    diameter: width * 1.00,
                    x: width * 0.08,
                    y: height * 0.84,
                    blur: 86
                )
                blob(
                    Color(hex: 0xFF9F0A),
                    opacity: dark ? 0.22 : 0.26,
                    diameter: width * 0.60,
                    x: width * 0.92,
                    y: height * 0.74,
                    blur: 68
                )
                blob(
                    Color(hex: 0x38BDF8),
                    opacity: dark ? 0.30 : 0.32,
                    diameter: width * 0.70,
                    x: width * 0.86,
                    y: height * 0.38,
                    blur: 74
                )

                Rectangle()
                    .fill(Material.ultraThin)

                (dark ? Color.black.opacity(0.30) : Color.white.opacity(0.04))
            }
            .frame(width: width, height: height)
            .animation(.easeInOut(duration: 0.45), value: accent)
        }
        .ignoresSafeArea()
    }

    private func base(dark: Bool) -> some View {
        LinearGradient(
            colors: dark
                ? [Color(hex: 0x070B16), Color(hex: 0x0D1224)]
                : [Color(hex: 0xF4F0FF), Color(hex: 0xEAF5FF)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func blob(
        _ color: Color,
        opacity: Double,
        diameter: CGFloat,
        x: CGFloat,
        y: CGFloat,
        blur: CGFloat
    ) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: diameter, height: diameter)
            .blur(radius: blur)
            .offset(x: x, y: y)
    }
}
