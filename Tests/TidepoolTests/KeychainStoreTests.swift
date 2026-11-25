import Foundation
import Testing
@testable import Tidepool

@Suite("钥匙串读写")
struct KeychainStoreTests {
    @Test func roundTrip() throws {
        let store = KeychainStore(service: "dev.pinellia.tidepool.tests")
        let id = UUID()
        defer { store.delete(id) }

        store.delete(id)
        #expect(store.get(id) == nil)

        try store.set("sk-test-123", for: id)
        #expect(store.get(id) == "sk-test-123")

        try store.set("sk-test-456", for: id)
        #expect(store.get(id) == "sk-test-456")

        store.delete(id)
        #expect(store.get(id) == nil)
    }
}
