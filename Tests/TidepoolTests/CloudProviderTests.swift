import Foundation
import Testing
@testable import Tidepool

@Suite("云厂商 CLI 解析")
struct CloudProviderTests {
    private func object(_ json: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(json.utf8))
    }

    @Test func volcengineCodingPlan() throws {
        let json = """
        {
          "items": [
            {
              "product": "coding-plan",
              "subscribed": true,
              "tier": "pro",
              "periods": [
                { "label": "session", "percent": 30, "reset_at": "2026-11-26T12:00:00Z" },
                { "label": "weekly", "percent": 50, "reset_at": "2026-11-30T00:00:00Z" },
                { "label": "monthly", "percent": 20, "reset_at": "2026-12-20T00:00:00Z" }
              ]
            }
          ]
        }
        """
        let snapshot = try VolcengineCLIProvider.parse(try object(json))
        #expect(snapshot.planName?.contains("Pro") == true)

        let five = try #require(snapshot.quotas.first { $0.kind == .fiveHour })
        let weekly = try #require(snapshot.quotas.first { $0.kind == .weekly })
        let monthly = try #require(snapshot.quotas.first { $0.kind == .monthly })
        #expect(abs(five.remainingPercent - 70) < 0.001)
        #expect(abs(weekly.remainingPercent - 50) < 0.001)
        #expect(abs(monthly.remainingPercent - 80) < 0.001)
        #expect(five.resetDate != nil)
    }

    @Test func volcengineNoSubscription() throws {
        let json = """
        { "items": [ { "product": "coding-plan", "subscribed": false } ] }
        """
        #expect(throws: (any Error).self) {
            try VolcengineCLIProvider.parse(try object(json))
        }
    }

    @Test func alibabaCodingPlan() throws {
        let json = """
        {
          "instanceType": "Pro",
          "per5Hour": { "percentage": 0.3, "resetTime": 1893456000 },
          "perWeek": { "usedQuota": 60, "totalQuota": 100 },
          "perBillMonth": { "percentage": 0.1, "resetTime": 1893456000000 }
        }
        """
        let snapshot = try AlibabaCLIProvider.parse(try object(json))
        #expect(snapshot.planName?.contains("Pro") == true)

        let five = try #require(snapshot.quotas.first { $0.kind == .fiveHour })
        let weekly = try #require(snapshot.quotas.first { $0.kind == .weekly })
        let monthly = try #require(snapshot.quotas.first { $0.kind == .monthly })
        #expect(abs(five.remainingPercent - 70) < 0.001)
        #expect(abs(weekly.remainingPercent - 40) < 0.001)
        #expect(abs(monthly.remainingPercent - 90) < 0.001)
    }

    @Test func alibabaEmptyMeansNoSubscription() throws {
        #expect(throws: (any Error).self) {
            try AlibabaCLIProvider.parse(try object("{}"))
        }
    }

    @Test func tencentBalanceInCents() throws {
        let json = """
        {
          "Response": {
            "Balance": 12345,
            "RealBalance": 12345,
            "CashAccountBalance": 10000,
            "PresentAccountBalance": 1000
          }
        }
        """
        let snapshot = try TencentCloudCLIProvider.parse(try object(json))
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "CNY")
        #expect(abs(balance.total - 123.45) < 0.001)
        #expect(abs((balance.granted ?? 0) - 10) < 0.001)
        #expect(abs((balance.toppedUp ?? 0) - 100) < 0.001)
    }

    @Test func huaweiBalances() throws {
        let json = """
        {
          "account_balances": [
            { "account_type": 1, "amount": "100.50", "currency": "CNY" },
            { "account_type": 5, "amount": "20.00", "currency": "CNY" }
          ],
          "currency": "CNY",
          "measure_id": 1
        }
        """
        let snapshot = try HuaweiCloudCLIProvider.parse(try object(json))
        let balance = try #require(snapshot.balance)
        #expect(abs(balance.total - 120.5) < 0.001)
        #expect(abs((balance.granted ?? 0) - 20) < 0.001)
    }
}

@Suite("Provider 图标资源")
struct ProviderArtworkTests {
    @Test @MainActor func allProviderArtworkLoads() {
        for provider in ProviderID.allCases {
            #expect(ProviderIconRenderer.icon(for: provider, colorMode: true, size: 18) != nil)
            #expect(ProviderIconRenderer.icon(for: provider, colorMode: false, size: 18) != nil)
        }
        #expect(ProviderIconRenderer.appMark(size: 18) != nil)
    }
}

@Suite("云凭据")
struct CloudCredentialTests {
    @Test func roundTrip() throws {
        let credentials = CloudCredentials(secretId: "AKIDEXAMPLE", secretKey: "SECRET")
        let encoded = try #require(credentials.encoded())
        let decoded = try #require(CloudCredentials.decode(encoded))
        #expect(decoded == credentials)
    }

    @Test func emptyCredentialsRejected() async {
        do {
            _ = try await TencentCloudProvider().fetch(apiKey: "", baseURL: nil)
            Issue.record("expected error")
        } catch {
            #expect(error is ProviderError)
        }
        do {
            _ = try await HuaweiCloudProvider().fetch(apiKey: "", baseURL: nil)
            Issue.record("expected error")
        } catch {
            #expect(error is ProviderError)
        }
    }
}

@Suite("腾讯云签名")
struct TencentSignatureTests {
    @Test func tc3Vector() {
        let signature = TencentCloudProvider.signature(
            secretKey: "TEST_SECRET",
            date: "2026-11-26",
            service: "billing",
            timestamp: 1_795_622_400,
            payload: "{}",
            host: "billing.tencentcloudapi.com",
            action: "DescribeAccountBalance"
        )
        #expect(signature == "2697d5bd68e5251d115ab9c71d1843253de3b4746184fca87999a4433e2ee5f1")
    }
}
