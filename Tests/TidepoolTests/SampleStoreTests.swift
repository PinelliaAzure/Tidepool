import Foundation
import Testing
@testable import Tidepool

@Suite("采样节流")
struct SampleStoreTests {
    @Test func quotaSamplingThrottle() {
        let store = SampleStore(persistent: false)
        let id = UUID()
        let now = Date()

        store.appendQuota(accountID: id, kind: .weekly, percent: 90, now: now)
        // 15 分钟内且变化 < 0.5%：丢弃
        store.appendQuota(accountID: id, kind: .weekly, percent: 89.8, now: now.addingTimeInterval(300))
        #expect(store.quotaSamples(for: id, kind: .weekly).count == 1)

        // 变化超过 0.5%：记录
        store.appendQuota(accountID: id, kind: .weekly, percent: 88, now: now.addingTimeInterval(400))
        #expect(store.quotaSamples(for: id, kind: .weekly).count == 2)

        // 超过 15 分钟：记录
        store.appendQuota(accountID: id, kind: .weekly, percent: 87, now: now.addingTimeInterval(1_200))
        #expect(store.quotaSamples(for: id, kind: .weekly).count == 3)

        // 不同 kind 独立
        store.appendQuota(accountID: id, kind: .fiveHour, percent: 60, now: now)
        #expect(store.quotaSamples(for: id, kind: .fiveHour).count == 1)
    }

    @Test func balanceSamplingThrottle() {
        let store = SampleStore(persistent: false)
        let id = UUID()
        let now = Date()

        store.append(accountID: id, value: 42.5, now: now)
        store.append(accountID: id, value: 42.5, now: now.addingTimeInterval(120))
        #expect(store.samples(for: id).count == 1)

        store.append(accountID: id, value: 40, now: now.addingTimeInterval(180))
        #expect(store.samples(for: id).count == 2)
    }

    @Test func purgeRemovesOnlyTargetAccount() {
        let store = SampleStore(persistent: false)
        let removed = UUID()
        let kept = UUID()
        let now = Date()

        store.append(accountID: removed, value: 10, now: now)
        store.append(accountID: kept, value: 20, now: now)
        store.appendQuota(accountID: removed, kind: .weekly, percent: 40, now: now)
        store.appendQuota(accountID: kept, kind: .weekly, percent: 60, now: now)

        store.purge(accountID: removed)

        #expect(store.samples(for: removed).isEmpty)
        #expect(store.quotaSamples(for: removed, kind: .weekly).isEmpty)
        #expect(store.samples(for: kept).count == 1)
        #expect(store.quotaSamples(for: kept, kind: .weekly).count == 1)
    }
}
