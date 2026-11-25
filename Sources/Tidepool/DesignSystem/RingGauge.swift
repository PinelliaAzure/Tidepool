import SwiftUI

/// 健康度配色：>=30% 绿，10–30% 橙，<10% 红。
enum HealthColor {
    static func color(for percent: Double) -> Color {
        if percent < 10 { return .red }
        if percent < 30 { return .orange }
        return .green
    }
}

/// 圆环进度：从 12 点方向顺时针填充剩余额度。
struct RingGauge: View {
    var progress: Double
    var tint: Color
    var lineWidth: CGFloat = 7
    var size: CGFloat = 78

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(0.004, min(progress, 1)))
                .stroke(
                    AngularGradient(
                        colors: [tint.opacity(0.55), tint],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: progress)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("剩余 \(Int((progress * 100).rounded()))%")
    }
}
