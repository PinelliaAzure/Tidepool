import SwiftUI

/// 计价时段卡片：闲时 / 标准价、24 小时时段条、下一次切换倒计时。
struct PricingCardView: View {
    let account: ProviderAccount

    var body: some View {
        if let schedule = ProviderPricing.schedule(for: account.provider) {
            let status = ProviderPricing.status(for: schedule)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(T("计价时段", "Pricing window")).sectionHeader()
                    Spacer()
                    Text(status.currentLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(status.isOffPeak ? Color.green : Color.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(
                                (status.isOffPeak ? Color.green : Color.secondary).opacity(0.12)
                            )
                        )
                }

                timeline(schedule: schedule, now: status.now)

                Text(status.schedule.peakDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Text(
                        status.isOffPeak
                            ? T("\(TideFormatter.countdownShort(to: status.nextTransition))后恢复标准价", "Standard price in \(TideFormatter.countdownShort(to: status.nextTransition))")
                            : T("\(TideFormatter.countdownShort(to: status.nextTransition))后进入闲时", "Off-peak in \(TideFormatter.countdownShort(to: status.nextTransition))")
                    )
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }

                Text(status.schedule.note)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .glassCard()
        }
    }

    /// 24 小时条：橙色为工作日标准价时段，竖线为当前时间。
    private func timeline(schedule: PricingSchedule, now: Date) -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = schedule.timeZone
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinute = CGFloat((components.hour ?? 0) * 60 + (components.minute ?? 0))
        let isWeekend = calendar.isDateInWeekend(now)

        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.06))

                if !isWeekend {
                    ForEach(Array(schedule.peakWindows.enumerated()), id: \.offset) { _, window in
                        let width = proxy.size.width * CGFloat(window.endMinute - window.startMinute) / 1440
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.orange.opacity(0.26))
                            .frame(width: width)
                            .offset(x: proxy.size.width * CGFloat(window.startMinute) / 1440)
                    }
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 1.2)
                    .offset(x: min(max(proxy.size.width * currentMinute / 1440, 0), proxy.size.width - 1))
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
        .overlay(alignment: .bottomLeading) {
            HStack {
                Text("00:00")
                Spacer()
                Text("12:00")
                Spacer()
                Text("24:00")
            }
            .font(.system(size: 8))
            .foregroundStyle(.tertiary)
            .offset(y: 11)
        }
        .padding(.bottom, 10)
    }
}
