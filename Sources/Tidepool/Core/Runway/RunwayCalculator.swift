import Foundation

struct RunwayReport: Equatable {
    var todaySpend: Double?
    var trailing7DaySpend: Double?
    var dailyBurn: Double?
    var daysLeft: Double?
}

/// 余额差值法：相邻两次采样的负差值计入消耗（按后一个采样所在日归档），
/// 正差值视为充值/到账，直接忽略。
enum RunwayCalculator {
    static func report(
        samples: [SamplePoint],
        currentBalance: Double,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RunwayReport {
        let sorted = samples.sorted { $0.date < $1.date }
        guard sorted.count >= 2 else { return RunwayReport() }

        var spendByDay: [Date: Double] = [:]
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            let delta = current.value - previous.value
            guard delta < 0 else { continue }
            let day = calendar.startOfDay(for: current.date)
            spendByDay[day, default: 0] += -delta
        }

        let todayKey = calendar.startOfDay(for: now)
        let todaySpend = spendByDay[todayKey]

        var trailing7DaySpend = 0.0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayKey) else { continue }
            trailing7DaySpend += spendByDay[day] ?? 0
        }

        let dailyBurn = trailing7DaySpend / 7
        let daysLeft = dailyBurn > 0 ? currentBalance / dailyBurn : nil

        return RunwayReport(
            todaySpend: todaySpend,
            trailing7DaySpend: trailing7DaySpend,
            dailyBurn: dailyBurn > 0 ? dailyBurn : nil,
            daysLeft: daysLeft
        )
    }
}
