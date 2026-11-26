import Foundation

/// 一个按本地时间定义的计价时段（分钟从 0 点起）。
struct PricingWindow: Equatable {
    var startMinute: Int
    var endMinute: Int
}

/// 某家 Provider 的时段计价规则。目前只有 DeepSeek 有官方闲时折扣；
/// 以后其他家推出类似规则时，在 ProviderPricing 里补一条即可。
struct PricingSchedule: Equatable {
    var timeZone: TimeZone
    /// Calendar 的 weekday：1 = 周日，2 = 周一 … 7 = 周六
    var peakWeekdays: Set<Int>
    var peakWindows: [PricingWindow]
    /// 闲时价格占标准价的比例（0.5 = 5 折）
    var offPeakFraction: Double
    var peakDetail: String
    var note: String

    var discountLabel: String {
        let percentOff = Int(((1 - offPeakFraction) * 100).rounded())
        if L10n.isEnglish {
            return "\(percentOff)% off"
        }
        if percentOff % 10 == 0 {
            return "\(percentOff / 10) 折"
        }
        return "\(percentOff)% off"
    }

    func isPeak(at date: Date, calendar: Calendar) -> Bool {
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              peakWeekdays.contains(weekday),
              let hour = components.hour,
              let minute = components.minute else { return false }
        let minutes = hour * 60 + minute
        return peakWindows.contains { minutes >= $0.startMinute && minutes < $0.endMinute }
    }

    /// 下一个计价状态切换点。
    func nextTransition(after date: Date, calendar: Calendar) -> Date? {
        var candidates: [Date] = []
        let startOfDay = calendar.startOfDay(for: date)
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            if let midnight = calendar.date(byAdding: .day, value: 1, to: day) {
                candidates.append(midnight)
            }
            for window in peakWindows {
                if let start = calendar.date(
                    bySettingHour: window.startMinute / 60,
                    minute: window.startMinute % 60,
                    second: 0,
                    of: day
                ) {
                    candidates.append(start)
                }
                if let end = calendar.date(
                    bySettingHour: window.endMinute / 60,
                    minute: window.endMinute % 60,
                    second: 0,
                    of: day
                ) {
                    candidates.append(end)
                }
            }
        }
        return candidates
            .filter { $0 > date }
            .sorted()
            .first { candidate in
                let before = isPeak(at: candidate.addingTimeInterval(-60), calendar: calendar)
                let after = isPeak(at: candidate.addingTimeInterval(60), calendar: calendar)
                return before != after
            }
    }
}

/// 当前时段状态，供菜单栏角标与面板卡片使用。
struct PricingStatus: Equatable {
    var isOffPeak: Bool
    var currentLabel: String
    var nextLabel: String
    var nextTransition: Date
    var schedule: PricingSchedule
    var now: Date

    var currentDetail: String {
        isOffPeak
            ? T(
                "当前闲时，价格为标准价的 \(schedule.discountLabel)",
                "Off-peak — \(schedule.discountLabel) the standard price"
            )
            : T(
                "当前标准价，\(TideFormatter.countdownShort(to: nextTransition)) 后进入闲时",
                "Standard price — off-peak starts in \(TideFormatter.countdownShort(to: nextTransition))"
            )
    }
}

enum ProviderPricing {
    static func schedule(for provider: ProviderID) -> PricingSchedule? {
        switch provider {
        case .deepseek:
            return PricingSchedule(
                timeZone: TimeZone(identifier: "Asia/Shanghai") ?? .current,
                peakWeekdays: [2, 3, 4, 5, 6],
                peakWindows: [
                    PricingWindow(startMinute: 9 * 60, endMinute: 12 * 60),
                    PricingWindow(startMinute: 14 * 60, endMinute: 18 * 60)
                ],
                offPeakFraction: 0.5,
                peakDetail: T(
                    "工作日 09:00–12:00 / 14:00–18:00 为标准价",
                    "Standard price on weekdays 09:00–12:00 and 14:00–18:00"
                ),
                note: T(
                    "闲时价格为标准价的 5 折；周末全天闲时，法定节假日以官方价格页为准。",
                    "Off-peak is 50% off; weekends are off-peak all day. Public holidays follow the official pricing page."
                )
            )
        case .moonshot, .kimiCode, .glm, .openrouter, .siliconFlow, .custom:
            return nil
        }
    }

    static func status(for provider: ProviderID, now: Date = Date()) -> PricingStatus? {
        guard let schedule = schedule(for: provider) else { return nil }
        return status(for: schedule, now: now)
    }

    static func status(for schedule: PricingSchedule, now: Date = Date()) -> PricingStatus {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = schedule.timeZone

        let isPeak = schedule.isPeak(at: now, calendar: calendar)
        let next = schedule.nextTransition(after: now, calendar: calendar)
            ?? now.addingTimeInterval(3600)
        let nextIsPeak = schedule.isPeak(at: next.addingTimeInterval(60), calendar: calendar)

        return PricingStatus(
            isOffPeak: !isPeak,
            currentLabel: isPeak
                ? T("标准价", "Peak")
                : T("闲时 \(schedule.discountLabel)", "Off-peak \(schedule.discountLabel)"),
            nextLabel: nextIsPeak
                ? T("标准价", "Peak")
                : T("闲时 \(schedule.discountLabel)", "Off-peak \(schedule.discountLabel)"),
            nextTransition: next,
            schedule: schedule,
            now: now
        )
    }

    /// 在指定时区显示 HH:mm。
    static func timeText(_ date: Date, in schedule: PricingSchedule) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = schedule.timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
