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

    @Test func deepSeekToleratesMissingOptionalBalances() throws {
        let json = """
        {
          "is_available": true,
          "balance_infos": [
            { "currency": "CNY", "total_balance": "12.00" }
          ]
        }
        """
        let snapshot = try DeepSeekProvider().parse(Data(json.utf8))
        let balance = try #require(snapshot.balance)
        #expect(abs(balance.total - 12) < 0.001)
        #expect((balance.granted ?? 0) == 0)
        #expect((balance.toppedUp ?? 0) == 0)
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

@Suite("OpenRouter / SiliconFlow 解析")
struct AdditionalProviderTests {
    @Test func openRouter() throws {
        let json = """
        { "data": { "total_credits": 100.0, "total_usage": 42.5 } }
        """
        let snapshot = try OpenRouterProvider().parse(Data(json.utf8))
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "USD")
        #expect(abs(balance.total - 57.5) < 0.001)
        #expect(abs((balance.toppedUp ?? 0) - 100) < 0.001)
        #expect(balance.isAvailable)
    }

    @Test func siliconFlow() throws {
        let json = """
        {
          "code": 20000,
          "status": true,
          "data": {
            "balance": "12.34",
            "chargeBalance": "20.00",
            "totalBalance": "12.34"
          }
        }
        """
        let snapshot = try SiliconFlowProvider().parse(Data(json.utf8))
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "CNY")
        #expect(abs(balance.total - 12.34) < 0.001)
        #expect(abs((balance.toppedUp ?? 0) - 20) < 0.001)
        #expect(balance.isAvailable)
    }

    @Test func siliconFlowInternationalCurrency() throws {
        let json = """
        {
          "code": 20000,
          "status": true,
          "data": {
            "balance": "1.20",
            "chargeBalance": "10.00",
            "totalBalance": "1.20"
          }
        }
        """
        let snapshot = try SiliconFlowProvider().parse(Data(json.utf8), currency: "USD")
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "USD")
        #expect(abs(balance.total - 1.20) < 0.001)
    }

    @Test func siliconFlowRetiredEndpointMessage() {
        let json = """
        { "code": 20092, "status": false, "message": "This endpoint is deprecated and is no longer available.", "data": null }
        """
        do {
            _ = try SiliconFlowProvider().parse(Data(json.utf8))
            Issue.record("expected a deprecation error")
        } catch let error as ProviderError {
            #expect(error.errorDescription?.contains("2026-08-14") == true)
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
