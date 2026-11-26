import SwiftUI

/// Hero 区：Provider 名称 + 状态 + 更新时间 + 大号余额 + 资金来源条。
struct BalanceHeroView: View {
    let account: ProviderAccount
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ProviderGlyph(provider: account.provider, size: 13)
                Text(account.name)
                    .font(.system(size: 13, weight: .semibold))
                if let balance = store.snapshots[account.id]?.balance {
                    Circle()
                        .fill(balance.isAvailable ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                }
                Spacer()
                if let updated = store.states[account.id]?.lastSuccess {
                    Text(TideFormatter.relative(updated) ?? "")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                refreshButton
            }

            if let balance = store.snapshots[account.id]?.balance {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(TideFormatter.currencySymbol(for: balance.currency))
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(store.privacyMode ? "•••" : TideFormatter.amount(balance.total, style: .hero))
                            .font(.system(size: 40, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    Text(T("可用余额", "Available balance"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if let granted = balance.granted,
                   let toppedUp = balance.toppedUp,
                   balance.total > 0 {
                    sourceBar(granted: granted, toppedUp: toppedUp, total: balance.total)
                }
            } else {
                Text("—")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .tertiaryText()
            }

            if let error = store.states[account.id]?.lastError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .glassCard()
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh(account.id, force: true) }
        } label: {
            if store.states[account.id]?.isRefreshing == true {
                ProgressView()
                    .controlSize(.mini)
            } else {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    /// 赠送余额 / 充值余额的构成条（DeepSeek / Kimi）。
    private func sourceBar(granted: Double, toppedUp: Double, total: Double) -> some View {
        let ratio = min(max(granted / total, 0), 1)
        return VStack(alignment: .leading, spacing: 5) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    Capsule()
                        .fill(account.provider.brandColor.opacity(0.75))
                        .frame(width: max(proxy.size.width * ratio, granted > 0 ? 4 : 0))
                    Capsule()
                        .fill(Color.primary.opacity(0.14))
                }
            }
            .frame(height: 5)
            HStack {
                Text(privacyMask(T("赠送 ", "Granted ") + TideFormatter.money(granted, currency: currencyCode, style: .hero)))
                Spacer()
                Text(privacyMask(T("充值 ", "Topped up ") + TideFormatter.money(toppedUp, currency: currencyCode, style: .hero)))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func privacyMask(_ text: String) -> String {
        store.privacyMode ? "•••" : text
    }

    private var currencyCode: String {
        store.snapshots[account.id]?.balance?.currency ?? "CNY"
    }
}
