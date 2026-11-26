import SwiftUI

/// 消耗与余量：今日消耗 / 7 天日均 / 预计可用（runway）。
struct RunwayView: View {
    let account: ProviderAccount
    @Environment(AppStore.self) private var store

    var body: some View {
        let report = RunwayCalculator.report(
            samples: store.samples(for: account.id),
            currentBalance: store.snapshots[account.id]?.balance?.total ?? 0
        )
        VStack(alignment: .leading, spacing: 10) {
            Text(T("消耗与余量", "Spend & runway")).sectionHeader()
            HStack(spacing: 0) {
                metric(T("今日消耗", "Today"), value: report.todaySpend.map(money) ?? "—")
                divider
                metric(T("7 天日均", "7-day avg"), value: report.dailyBurn.map(money) ?? "—")
                divider
                metric(T("预计可用", "Runway"), value: report.daysLeft.map { TideFormatter.duration(days: $0) } ?? T("暂无消耗", "No spend yet"))
            }
        }
        .glassCard()
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1, height: 28)
    }

    private func metric(_ title: String, value: String) -> some View {
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

    private func money(_ value: Double) -> String {
        if store.privacyMode { return "•••" }
        let currency = store.snapshots[account.id]?.balance?.currency ?? "CNY"
        return TideFormatter.money(value, currency: currency, style: .hero)
    }
}

/// Footer：刷新间隔 + 打开官方平台。
struct PopoverFooterView: View {
    let account: ProviderAccount
    @Environment(AppStore.self) private var store

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { account.intervalSeconds },
            set: { newValue in
                store.updateAccount(id: account.id) { $0.intervalSeconds = newValue }
            }
        )
    }

    var body: some View {
        HStack(spacing: 12) {
            Picker(T("刷新间隔", "Refresh"), selection: intervalBinding) {
                Text(T("1 分钟", "1 min")).tag(60)
                Text(T("5 分钟", "5 min")).tag(300)
                Text(T("10 分钟", "10 min")).tag(600)
                Text(T("30 分钟", "30 min")).tag(1800)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()

            Spacer()

            Link(destination: account.provider.platformURL) {
                HStack(spacing: 3) {
                    Text(T("打开平台", "Open platform"))
                    Image(systemName: "arrow.up.right")
                }
                .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
}
