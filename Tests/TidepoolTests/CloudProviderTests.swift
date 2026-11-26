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

    @Test @MainActor func kimiCodeIconHasCodeBadge() throws {
        for colorMode in [true, false] {
            let kimi = try #require(ProviderIconRenderer.icon(for: .moonshot, colorMode: colorMode, size: 18))
            let kimiCode = try #require(ProviderIconRenderer.icon(for: .kimiCode, colorMode: colorMode, size: 18))
            let kimiData = try #require(kimi.tiffRepresentation)
            let codeData = try #require(kimiCode.tiffRepresentation)
            #expect(kimiData != codeData)
        }
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
            date: "2026-11-25",
            service: "billing",
            timestamp: 1_795_622_400,
            payload: "{}",
            host: "billing.tencentcloudapi.com"
        )
        #expect(signature == "2869944301bcc71c563fa74e09381b65494299a9cfd8547bf2d0e1f2cbe98a58")
    }
}

@Suite("阿里云余额解析")
struct AlibabaCloudBalanceTests {
    @Test func parseAvailableAmount() throws {
        let json = """
        {
          "Code": "200",
          "Message": "success",
          "Success": true,
          "Data": {
            "AvailableAmount": "10000.00",
            "AvailableCashAmount": "8000.00",
            "CreditAmount": "0.00",
            "Currency": "CNY"
          }
        }
        """
        let snapshot = try AlibabaCloudProvider.parse(Data(json.utf8))
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "CNY")
        #expect(abs(balance.total - 10000) < 0.001)
        #expect(abs((balance.toppedUp ?? 0) - 8000) < 0.001)
        #expect(balance.isAvailable)
    }

    @Test func failedResponseThrows() {
        let json = """
        { "Code": "NotAuthorized", "Message": "not authorized", "Success": false }
        """
        #expect(throws: (any Error).self) {
            try AlibabaCloudProvider.parse(Data(json.utf8))
        }
    }
}

@Suite("阿里云签名")
struct AlibabaSignatureTests {
    @Test func rpcVector() {
        let params: [(String, String)] = [
            ("AccessKeyId", "testid"),
            ("Action", "DescribeRegions"),
            ("Format", "XML"),
            ("SignatureMethod", "HMAC-SHA1"),
            ("SignatureNonce", "3ee8c1b8-83d3-44af-a94f-4e0ad82fd6cf"),
            ("SignatureVersion", "1.0"),
            ("Timestamp", "2016-02-23T12:46:24Z"),
            ("Version", "2014-05-26")
        ]
        let canonical = AlibabaCloudProvider.canonicalQuery(params)
        #expect(canonical == "AccessKeyId=testid&Action=DescribeRegions&Format=XML&SignatureMethod=HMAC-SHA1&SignatureNonce=3ee8c1b8-83d3-44af-a94f-4e0ad82fd6cf&SignatureVersion=1.0&Timestamp=2016-02-23T12%3A46%3A24Z&Version=2014-05-26")
        #expect(AlibabaCloudProvider.signature(secretKey: "testsecret", canonicalQuery: canonical) == "OLeaidS1JvxuMvnyHOwuJ+uX5qY=")
    }
}

@Suite("华为云签名")
struct HuaweiSignatureTests {
    @Test func sdkVector() {
        let signature = HuaweiCloudProvider.signature(
            secretKey: "SECRETKEYEXAMPLE",
            path: "/v2/accounts/customer-accounts/balances",
            host: "bss.myhuaweicloud.com",
            timestamp: "20261126T120000Z"
        )
        #expect(signature == "4582d5b66557d5b57905b52eab5affd38f10ff0f8c1c4018c1e29b5db200aa1c")
    }
}

@Suite("火山方舟未登录")
struct VolcengineLoginErrorTests {
    @Test func notConfiguredBecomesActionable() throws {
        let json = """
        {
          "ok": false,
          "error": {
            "type": "error",
            "message": "not configured, run `arkcli config init --profile default` or `arkcli auth login`",
            "trace_id": "test"
          }
        }
        """
        do {
            _ = try VolcengineCLIProvider.parse(try JSONSerialization.jsonObject(with: Data(json.utf8)))
            Issue.record("expected an error")
        } catch let error as ProviderError {
            let message = try #require(error.errorDescription)
            #expect(message.contains("登录") || message.lowercased().contains("sign in"))
        }
    }
}

@Suite("CLI 结构化错误")
struct CLIIntegrationTests {
    @Test func structuredErrorFromStderr() throws {
        let script = "printf '%s' '{\"ok\":false,\"error\":{\"message\":\"not configured\"}}' >&2; exit 1"
        let json = try CLIExecutor.json(tool: "sh", arguments: ["-c", script], installHint: "")
        let root = try #require(json as? [String: Any])
        #expect(root["ok"] as? Bool == false)
        let error = try #require(root["error"] as? [String: Any])
        #expect(error["message"] as? String == "not configured")
    }
}
