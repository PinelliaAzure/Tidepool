import Foundation
import Testing
@testable import Tidepool

@Suite("提醒规划")
struct AlertPlannerTests {
    init() { L10n.overrideEnglish = false }

    private func account() -> ProviderAccount {
        ProviderAccount(provider: .deepseek, name: "DeepSeek")
    }

    private func snapshot(balance: Double?, quotas: [QuotaWindow]) -> ProviderSnapshot {
        ProviderSnapshot(
            fetchedAt: Date(),
            balance: balance.map {
                BalanceSnapshot(currency: "CNY", total: $0, granted: nil, toppedUp: nil, isAvailable: true)
            },
            quotas: quotas
        )
    }

    @Test func lowBalance() {
        let events = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(balance: 8.5, quotas: []),
            lowBalanceThreshold: 10
        )
        #expect(events.count == 1)
        #expect(events[0].key.hasPrefix("balance-"))
        #expect(events[0].title.contains("DeepSeek"))
        #expect(events[0].body.contains("¥8.50"))
    }

    @Test func healthyBalanceNoEvent() {
        let events = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(balance: 42, quotas: [])
        )
        #expect(events.isEmpty)
    }

    @Test func lowQuotaAndResetSoon() {
        let now = Date()
        let reset = now.addingTimeInterval(30 * 60)
        let quota = QuotaWindow(kind: .weekly, remainingPercent: 8, resetDate: reset)

        let events = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(balance: nil, quotas: [quota]),
            now: now
        )
        // 低额度 + 即将重置
        #expect(events.count == 2)
        #expect(events.contains { $0.key.hasPrefix("quota-") })
        #expect(events.contains { $0.key.hasPrefix("reset-") })
        #expect(events.allSatisfy { $0.body.contains("8%") })
    }

    @Test func resetOnlyWithinWindow() {
        let now = Date()
        // 50% 剩余，1 小时内重置 → 只有重置提醒
        let soon = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(
                balance: nil,
                quotas: [QuotaWindow(kind: .fiveHour, remainingPercent: 50, resetDate: now.addingTimeInterval(59 * 60))]
            ),
            now: now
        )
        #expect(soon.count == 1)
        #expect(soon[0].key.hasPrefix("reset-"))

        // 2 小时后 → 不提醒
        let later = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(
                balance: nil,
                quotas: [QuotaWindow(kind: .fiveHour, remainingPercent: 50, resetDate: now.addingTimeInterval(2 * 3600))]
            ),
            now: now
        )
        #expect(later.isEmpty)
    }

    @Test func resetCanBeDisabled() {
        let now = Date()
        let events = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(
                balance: nil,
                quotas: [QuotaWindow(kind: .weekly, remainingPercent: 60, resetDate: now.addingTimeInterval(1800))]
            ),
            now: now,
            includeReset: false
        )
        #expect(events.isEmpty)
    }

    @Test func cycleKeyChangesAfterReset() {
        let now = Date()
        let quotaA = QuotaWindow(kind: .weekly, remainingPercent: 5, resetDate: now.addingTimeInterval(600))
        let quotaB = QuotaWindow(kind: .weekly, remainingPercent: 5, resetDate: now.addingTimeInterval(7 * 86_400))

        let eventsA = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(balance: nil, quotas: [quotaA]),
            now: now
        )
        let eventsB = AlertPlanner.events(
            account: account(),
            snapshot: snapshot(balance: nil, quotas: [quotaB]),
            now: now
        )
        let keyA = eventsA.first { $0.key.hasPrefix("quota-") }?.key
        let keyB = eventsB.first { $0.key.hasPrefix("quota-") }?.key
        #expect(keyA != nil)
        #expect(keyB != nil)
        #expect(keyA != keyB)
    }
}
