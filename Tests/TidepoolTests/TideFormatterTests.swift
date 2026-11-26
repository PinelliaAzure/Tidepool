import Foundation
import Testing
@testable import Tidepool

@Suite("金额与时长格式化")
struct TideFormatterTests {
    init() { L10n.overrideEnglish = false }

    @Test func menuBarMoneyFormat() {
        #expect(TideFormatter.money(42.5, currency: "CNY", style: .menuBar) == "¥42.50")
        #expect(TideFormatter.money(1284, currency: "CNY", style: .menuBar) == "¥1,284")
        #expect(TideFormatter.money(12800, currency: "CNY", style: .menuBar) == "¥12.8k")
        #expect(TideFormatter.money(9.9, currency: "USD", style: .menuBar) == "$9.90")
    }

    @Test func heroMoneyFormat() {
        #expect(TideFormatter.money(0.5, currency: "CNY", style: .hero) == "¥0.50")
        #expect(TideFormatter.money(1234.5, currency: "USD", style: .hero) == "$1,234.50")
    }

    @Test func percent() {
        #expect(TideFormatter.percent(72.4) == "72%")
        #expect(TideFormatter.percent(0.4) == "0%")
    }

    @Test func duration() {
        #expect(TideFormatter.duration(days: 13.2) == "13 天")
        #expect(TideFormatter.duration(days: 3.45) == "3.5 天")
        #expect(TideFormatter.duration(days: 0.4) == "10 小时")
        #expect(TideFormatter.duration(days: 0.01) == "14 分钟")
    }

    @Test func relativeTime() {
        let now = Date()
        #expect(TideFormatter.relative(now.addingTimeInterval(-5), now: now) == "刚刚")
        #expect(TideFormatter.relative(now.addingTimeInterval(5), now: now) == "刚刚")
    }
}
