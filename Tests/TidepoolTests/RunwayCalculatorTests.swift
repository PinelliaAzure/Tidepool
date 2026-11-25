import Foundation
import Testing
@testable import Tidepool

@Suite("Runway 计算")
struct RunwayCalculatorTests {
    private func point(daysAgo: Int, value: Double, now: Date) -> SamplePoint {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!
        return SamplePoint(date: date, value: value)
    }

    @Test func dailyBurnAndRunway() {
        let now = Date()
        // 时间从远到近：100 → 93，7 个完整消耗日，每天消耗 1
        let samples = (0...7).map { point(daysAgo: $0, value: 100 - Double(7 - $0), now: now) }

        let report = RunwayCalculator.report(samples: samples, currentBalance: 93, now: now)

        #expect(abs((report.trailing7DaySpend ?? 0) - 7) < 0.001)
        #expect(abs((report.dailyBurn ?? 0) - 1) < 0.001)
        #expect(abs((report.daysLeft ?? 0) - 93) < 0.001)
    }

    @Test func topUpIsIgnored() {
        let now = Date()
        let values: [(Int, Double)] = [
            (6, 100), (5, 90), (4, 190), (3, 180), (2, 170), (1, 160), (0, 150)
        ]
        let samples = values.map { point(daysAgo: $0.0, value: $0.1, now: now) }

        let report = RunwayCalculator.report(samples: samples, currentBalance: 150, now: now)

        // 只有负差值计入消耗：5 段 × 10 = 50，充值的 +100 被忽略
        #expect(abs((report.trailing7DaySpend ?? 0) - 50) < 0.001)
        #expect(abs((report.daysLeft ?? 0) - 150 / (50.0 / 7)) < 0.01)
    }

    @Test func insufficientSamples() {
        let now = Date()
        let single = [point(daysAgo: 0, value: 42, now: now)]

        let report = RunwayCalculator.report(samples: single, currentBalance: 42, now: now)
        #expect(report.dailyBurn == nil)
        #expect(report.daysLeft == nil)

        let empty = RunwayCalculator.report(samples: [], currentBalance: 42, now: now)
        #expect(empty.dailyBurn == nil)
    }

    @Test func todaySpend() {
        let now = Date()
        let samples = [
            point(daysAgo: 1, value: 50, now: now),
            point(daysAgo: 0, value: 45, now: now)
        ]
        let report = RunwayCalculator.report(samples: samples, currentBalance: 45, now: now)
        #expect(abs((report.todaySpend ?? 0) - 5) < 0.001)
    }
}
