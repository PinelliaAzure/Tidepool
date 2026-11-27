import Foundation
import Testing
@testable import Tidepool

@Suite("应用内更新")
struct UpdateServiceTests {
    @Test func versionComparison() {
        #expect(UpdateService.isNewer("0.4.13", than: "0.4.12"))
        #expect(UpdateService.isNewer("0.5.0", than: "0.4.12"))
        #expect(UpdateService.isNewer("1.0", than: "0.9.9"))
        #expect(UpdateService.isNewer("0.4.12.1", than: "0.4.12"))
        #expect(!UpdateService.isNewer("0.4.12", than: "0.4.12"))
        #expect(!UpdateService.isNewer("0.4.9", than: "0.4.12"))
        #expect(!UpdateService.isNewer("0.4", than: "0.4.0"))
    }
}
