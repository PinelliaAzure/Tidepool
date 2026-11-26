import Foundation
import Testing
@testable import Tidepool

@Suite("DeepSeek 计价时段")
struct PricingScheduleTests {
    init() { L10n.overrideEnglish = false }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        ))!
    }

    private var schedule: PricingSchedule {
        ProviderPricing.schedule(for: .deepseek)!
    }

    @Test func weekdayPeakWindows() {
        // 周三 10:00 标准价，12:00 进入闲时
        let status = ProviderPricing.status(for: schedule, now: date(2026, 11, 25, 10, 0))
        #expect(!status.isOffPeak)
        #expect(status.currentLabel == "标准价")
        #expect(calendar.component(.hour, from: status.nextTransition) == 12)
        #expect(calendar.component(.minute, from: status.nextTransition) == 0)
        #expect(status.nextLabel.contains("闲时"))
    }

    @Test func lunchBreakIsOffPeak() {
        let status = ProviderPricing.status(for: schedule, now: date(2026, 11, 25, 12, 30))
        #expect(status.isOffPeak)
        #expect(status.currentLabel.contains("5 折"))
        #expect(calendar.component(.hour, from: status.nextTransition) == 14)
    }

    @Test func boundaryBeforeNine() {
        let status = ProviderPricing.status(for: schedule, now: date(2026, 11, 25, 8, 59))
        #expect(status.isOffPeak)
        #expect(calendar.component(.hour, from: status.nextTransition) == 9)
    }

    @Test func boundaryAtNine() {
        let status = ProviderPricing.status(for: schedule, now: date(2026, 11, 25, 9, 0))
        #expect(!status.isOffPeak)
    }

    @Test func eveningBoundary() {
        let before = ProviderPricing.status(for: schedule, now: date(2026, 11, 25, 17, 59))
        #expect(!before.isOffPeak)
        #expect(calendar.component(.hour, from: before.nextTransition) == 18)

        let after = ProviderPricing.status(for: schedule, now: date(2026, 11, 25, 18, 0))
        #expect(after.isOffPeak)
    }

    @Test func weekendIsAllOffPeak() {
        // 周六 10:00 闲时；下一次切换应是周一 09:00
        let status = ProviderPricing.status(for: schedule, now: date(2026, 11, 28, 10, 0))
        #expect(status.isOffPeak)

        let next = status.nextTransition
        #expect(calendar.component(.weekday, from: next) == 2) // 周一
        #expect(calendar.component(.hour, from: next) == 9)
        #expect(calendar.component(.minute, from: next) == 0)
    }

    @Test func fridayEveningJumpsToMonday() {
        // 周五 19:00 闲时，下一次切换应为周一 09:00（周末没有时段切换）
        let status = ProviderPricing.status(for: schedule, now: date(2026, 11, 27, 19, 0))
        #expect(status.isOffPeak)
        let next = status.nextTransition
        #expect(calendar.component(.weekday, from: next) == 2)
        #expect(calendar.component(.hour, from: next) == 9)
    }

    @Test func noScheduleForOtherProviders() {
        #expect(ProviderPricing.schedule(for: .glm) == nil)
        #expect(ProviderPricing.schedule(for: .kimiCode) == nil)
        #expect(ProviderPricing.schedule(for: .moonshot) == nil)
        #expect(ProviderPricing.schedule(for: .deepseek) != nil)
    }

    @Test func shortCountdownText() {
        let now = date(2026, 11, 25, 10, 0)
        let next = date(2026, 11, 25, 12, 0)
        #expect(TideFormatter.countdownShort(to: next, now: now) == "2 小时")
        #expect(TideFormatter.countdown(to: next, now: now) == "2 小时后重置")
    }
}
