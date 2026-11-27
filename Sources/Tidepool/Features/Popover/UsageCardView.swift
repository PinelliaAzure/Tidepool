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
                    Text(T("本地用量", "Local usage")).sectionHeader()
                    Spacer()
                    Button {
                        appStore.requestUsage()
                    } label: {
                        HStack(spacing: 2) {
                            Text(T("明细", "Details"))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 8) {
                    metric(T("近 7 天", "Last 7 days"), TideFormatter.tokens(summary.totalTokens(days: 7)))
                    metric(T("估算费用", "Est. cost"), costText(summary.totalCost(days: 7)))
                    metric(
                        T("缓存命中", "Cache hit"),
                        summary.cacheHitRate(days: 7).map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
                    )
                }
            }
            .glassCard()
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func costText(_ value: Double) -> String {
        if appStore.privacyMode { return "•••" }
        guard value > 0 else { return "—" }
        return "≈ " + TideFormatter.usd(value)
    }
}
