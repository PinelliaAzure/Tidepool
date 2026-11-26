import Foundation
import Testing
@testable import Tidepool

@Suite("额度节奏判断")
struct QuotaPaceTests {
    init() { L10n.overrideEnglish = false }

    private func quota(kind: QuotaKind, remaining: Double, resetIn: TimeInterval) -> QuotaWindow {
        QuotaWindow(
            kind: kind,
            remainingPercent: remaining,
            resetDate: Date().addingTimeInterval(resetIn)
        )
    }

    @Test func onPace() throws {
        // 周额度：时间过去一半，已用一半
        let status = try #require(
            QuotaPace.status(quota: quota(kind: .weekly, remaining: 50, resetIn: 3.5 * 86_400))
        )
        #expect(status.text.contains("节奏正常"))
    }

    @Test func tooFast() throws {
        let status = try #require(
            QuotaPace.status(quota: quota(kind: .weekly, remaining: 20, resetIn: 3.5 * 86_400))
        )
        #expect(status.isFast)
        #expect(status.text.contains("偏快"))
    }

    @Test func comfortable() throws {
        let status = try #require(
            QuotaPace.status(quota: quota(kind: .fiveHour, remaining: 90, resetIn: 2.5 * 3600))
        )
        #expect(!status.isFast)
        #expect(status.text.contains("从容"))
    }

    @Test func expiredWindowReturnsNil() {
        let status = QuotaPace.status(quota: quota(kind: .fiveHour, remaining: 50, resetIn: -10))
        #expect(status == nil)
    }
}
