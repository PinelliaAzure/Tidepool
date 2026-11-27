import Charts
import SwiftUI

/// 额度型 Provider（GLM / Kimi Code / 火山方舟 / 阿里云百炼）的 Hero：
/// 双环（5 小时 / 本周）+ 重置倒计时 + 节奏判断；月额度单独一行。
struct QuotaHeroView: View {
    let account: ProviderAccount
    @Environment(AppStore.self) private var store

    var body: some View {
        let snapshot = store.snapshots[account.id]
        let quotas = snapshot?.sortedQuotas ?? []
        let primaryQuotas = quotas.filter { $0.kind != .monthly }

        VStack(alignment: .leading, spacing: 12) {
            header(snapshot)

            if primaryQuotas.isEmpty {
                Text(T("正在读取套餐额度…", "Reading plan quota…"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(primaryQuotas) { quota in
                        ringCard(quota)
                    }
                    if primaryQuotas.count == 1 {
                        Spacer()
                    }
                }
                if let pace {
                    paceRow(pace)
                }
                if let monthly = quotas.first(where: { $0.kind == .monthly }) {
                    monthlyRow(monthly)
                }
                if let history = weeklyHistory {
                    historyChart(history)
                }
            }

            if let error = store.states[account.id]?.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .glassCard()
    }

    // MARK: - 组件

    private func header(_ snapshot: ProviderSnapshot?) -> some View {
        HStack(spacing: 8) {
            ProviderGlyph(provider: account.provider, size: 13)
            Text(account.name)
                .font(.system(size: 13, weight: .semibold))

            if let plan = snapshot?.planName {
                Text(plan)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(account.provider.brandColor.opacity(0.12))
                    )
            }

            Spacer()

            if let updated = store.states[account.id]?.lastSuccess {
                Text(TideFormatter.relative(updated) ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            refreshButton
        }
    }

    private func ringCard(_ quota: QuotaWindow) -> some View {
        VStack(spacing: 6) {
            ZStack {
                RingGauge(
                    progress: quota.remainingFraction,
                    tint: HealthColor.color(for: quota.remainingPercent),
                    lineWidth: 7,
                    size: 76
                )
                VStack(spacing: 0) {
                    Text(TideFormatter.percent(quota.remainingPercent))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(T("剩余", "left"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Text(quota.kind.displayName)
                .font(.caption2.weight(.medium))
            if let reset = quota.resetDate {
                Text(TideFormatter.countdown(to: reset))
                    .font(.system(size: 10))
                    .tertiaryText()
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func paceRow(_ pace: QuotaPace.Status) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: pace.isFast ? "exclamationmark.gauge" : "speedometer")
                .font(.system(size: 11))
                .foregroundStyle(pace.isFast ? Color.orange : Color.secondary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(pace.text)
                    .font(.caption)
                    .foregroundStyle(pace.isFast ? Color.orange : Color.primary)
                Text(pace.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }

    /// 月额度文案：GLM 的月额度是网页工具（MCP）额度，其他家是普通月度配额。
    private var monthlyLabel: String {
        switch account.provider {
        case .glm:
            return T("网页工具 · 本月", "Web tools · monthly")
        default:
            return T("本月额度", "Monthly quota")
        }
    }

    private func monthlyRow(_ quota: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(monthlyLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TideFormatter.percent(quota.remainingPercent))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                if let reset = quota.resetDate {
                    Text(TideFormatter.countdown(to: reset))
                        .font(.caption2)
                        .tertiaryText()
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(HealthColor.color(for: quota.remainingPercent))
                        .frame(width: max(proxy.size.width * quota.remainingFraction, 3))
                }
            }
            .frame(height: 4)
        }
    }

    private func historyChart(_ points: [QuotaSamplePoint]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(T("本周额度走势", "Weekly quota trend"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(T("近 7 天", "Last 7 days"))
                    .font(.system(size: 9))
                    .tertiaryText()
            }

            Chart(points) { point in
                AreaMark(
                    x: .value(T("时间", "Time"), point.date),
                    y: .value(T("剩余", "Remaining"), point.remainingPercent)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [account.provider.brandColor.opacity(0.24), account.provider.brandColor.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value(T("时间", "Time"), point.date),
                    y: .value(T("剩余", "Remaining"), point.remainingPercent)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(account.provider.brandColor)
                .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 50, 100]) { value in
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text("\(Int(percent))%")
                                .font(.system(size: 9))
                                .tertiaryText()
                        }
                    }
                }
            }
            .frame(height: 58)
        }
        .padding(.top, 2)
    }

    private var weeklyHistory: [QuotaSamplePoint]? {
        guard let snapshot = store.snapshots[account.id],
              snapshot.quotas.contains(where: { $0.kind == .weekly }) else { return nil }
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        let points = store.quotaSamples(for: account.id, kind: .weekly).filter { $0.date >= cutoff }
        return points.count >= 2 ? points : nil
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh(account.id, force: true) }
        } label: {
            if store.states[account.id]?.isRefreshing == true {
                ProgressView().controlSize(.mini)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var pace: QuotaPace.Status? {
        guard let snapshot = store.snapshots[account.id] else { return nil }
        let quota = snapshot.quotas.first { $0.kind == .weekly } ?? snapshot.tightestQuota
        guard let quota else { return nil }
        return QuotaPace.status(quota: quota)
    }
}
