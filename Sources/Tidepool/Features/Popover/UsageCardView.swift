import SwiftUI

/// 面板底部的本地用量摘要卡。
struct UsageCardView: View {
    @Environment(UsageStore.self) private var usageStore
    @Environment(AppStore.self) private var appStore

    var body: some View {
        if usageStore.enabled, !usageStore.records.isEmpty {
            let summary = usageStore.summary
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("本地用量").sectionHeader()
                    Spacer()
                    Button {
                        appStore.requestUsage()
                    } label: {
                        HStack(spacing: 2) {
                            Text("明细")
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 0) {
                    metric("近 7 天", TideFormatter.tokens(summary.totalTokens(days: 7)))
                    divider
                    metric("估算费用", costText(summary.totalCost(days: 7)))
                    divider
                    metric(
                        "缓存命中",
                        summary.cacheHitRate(days: 7).map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
                    )
                }
            }
            .glassCard()
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 26)
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func costText(_ value: Double) -> String {
        if appStore.privacyMode { return "•••" }
        guard value > 0 else { return "—" }
        return "≈ " + TideFormatter.usd(value)
    }
}
