import Foundation
import Testing
@testable import Tidepool

@Suite("通知去重记录")
struct NotificationManagerTests {
    @Test @MainActor func trimsToNewestKeys() {
        let now = Date()
        var keys: [String: Date] = [:]
        for index in 0..<300 {
            keys["k\(index)"] = now.addingTimeInterval(TimeInterval(index))
        }

        let trimmed = NotificationManager.trimmed(keys)

        #expect(trimmed.count == 200)
        #expect(trimmed["k299"] != nil)
        #expect(trimmed["k100"] != nil)
        #expect(trimmed["k99"] == nil)
    }

    @Test @MainActor func keepsAllWhenUnderLimit() {
        let keys = ["a": Date(), "b": Date()]
        #expect(NotificationManager.trimmed(keys).count == 2)
    }
}
