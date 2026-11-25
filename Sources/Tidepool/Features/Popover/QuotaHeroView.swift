import SwiftUI

/// 额度型 Provider（GLM / Kimi Code）的 Hero：
/// 双环（5 小时 / 本周）+ 重置倒计时 + 节奏判断。
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
                Text("正在读取套餐额度…")
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
            Circle()
                .fill(account.provider.brandColor)
                .frame(width: 8, height: 8)
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
                    Text("剩余")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            Text(quota.kind.displayName)
                .font(.caption2.weight(.medium))
            if let reset = quota.resetDate {
                Text(TideFormatter.countdown(to: reset))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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

    private func monthlyRow(_ quota: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("网页工具 · 本月")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(TideFormatter.percent(quota.remainingPercent))
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                if let reset = quota.resetDate {
                    Text(TideFormatter.countdown(to: reset))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
