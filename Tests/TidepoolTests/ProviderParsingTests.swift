import Foundation
import Testing
@testable import Tidepool

@Suite("Provider 响应解析")
struct ProviderParsingTests {
    @Test func deepSeekParsing() throws {
        let json = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "110.00",
              "granted_balance": "10.00",
              "topped_up_balance": "100.00"
            }
          ]
        }
        """
        let snapshot = try DeepSeekProvider().parse(Data(json.utf8))
        let balance = try #require(snapshot.balance)

        #expect(balance.currency == "CNY")
        #expect(abs(balance.total - 110) < 0.001)
        #expect(abs((balance.granted ?? 0) - 10) < 0.001)
        #expect(abs((balance.toppedUp ?? 0) - 100) < 0.001)
        #expect(balance.isAvailable)
        #expect(snapshot.quotas.isEmpty)
    }

    @Test func deepSeekMissingBalanceInfosThrows() {
        let json = """
        { "is_available": false, "balance_infos": [] }
        """
        #expect(throws: (any Error).self) {
            try DeepSeekProvider().parse(Data(json.utf8))
        }
    }

    @Test func moonshotParsing() throws {
        let json = """
        {
          "code": 0,
          "data": {
            "available_balance": 49.58894,
            "voucher_balance": 46.58893,
            "cash_balance": 3.00001
          },
          "scode": "0x0",
          "status": true
        }
        """
        let snapshot = try MoonshotProvider().parse(Data(json.utf8))
        let balance = try #require(snapshot.balance)

        #expect(balance.currency == "CNY")
        #expect(abs(balance.total - 49.58894) < 0.001)
        #expect(abs((balance.granted ?? 0) - 46.58893) < 0.001)
        #expect(abs((balance.toppedUp ?? 0) - 3.00001) < 0.001)
        #expect(balance.isAvailable)
    }

    @Test func moonshotMissingDataThrows() {
        let json = """
        { "code": 1, "data": null, "status": false }
        """
        #expect(throws: (any Error).self) {
            try MoonshotProvider().parse(Data(json.utf8))
        }
    }

    @Test func accountCodingRoundTrip() throws {
        let account = ProviderAccount(provider: .deepseek, name: "主力", intervalSeconds: 600, sortOrder: 2)
        let data = try JSONEncoder().encode([account])
        let decoded = try JSONDecoder().decode([ProviderAccount].self, from: data)

        #expect(decoded == [account])
    }
}
