import Foundation
import Testing
@testable import Tidepool

@Suite("自定义接口解析")
struct CustomProviderTests {
    private func config(
        balancePath: String = "",
        percentPath: String = "",
        percentIsUsed: Bool = false,
        remainingPath: String = "",
        totalPath: String = "",
        resetPath: String = ""
    ) -> CustomEndpointConfig {
        CustomEndpointConfig(
            endpoint: "https://example.com/balance",
            authStyle: .bearer,
            currency: "USD",
            balancePath: balancePath,
            percentPath: percentPath,
            percentIsUsed: percentIsUsed,
            remainingPath: remainingPath,
            totalPath: totalPath,
            resetPath: resetPath,
            title: "My API"
        )
    }

    @Test func balanceFromString() throws {
        let json = """
        { "data": { "balance": "42.50" } }
        """
        let snapshot = try CustomEndpointProvider(config: config(balancePath: "data.balance"))
            .parse(Data(json.utf8))
        let balance = try #require(snapshot.balance)
        #expect(balance.currency == "USD")
        #expect(abs(balance.total - 42.5) < 0.001)
        #expect(snapshot.planName == "My API")
    }

    @Test func percentRemaining() throws {
        let json = """
        { "data": { "limits": [{ "remaining_percent": 73 }] } }
        """
        let snapshot = try CustomEndpointProvider(
            config: config(percentPath: "data.limits.0.remaining_percent")
        ).parse(Data(json.utf8))

        let quota = try #require(snapshot.quotas.first)
        #expect(quota.kind == .custom)
        #expect(abs(quota.remainingPercent - 73) < 0.001)
        #expect(snapshot.balance == nil)
    }

    @Test func percentUsed() throws {
        let json = """
        { "usage": { "used_percent": 30 } }
        """
        let snapshot = try CustomEndpointProvider(
            config: config(percentPath: "usage.used_percent", percentIsUsed: true)
        ).parse(Data(json.utf8))

        #expect(abs((snapshot.quotas.first?.remainingPercent ?? 0) - 70) < 0.001)
    }

    @Test func remainingOverTotalAndReset() throws {
        let json = """
        {
          "quota": { "remaining": 40, "total": 100, "reset_at": 1893456000000 }
        }
        """
        let snapshot = try CustomEndpointProvider(
            config: config(
                remainingPath: "quota.remaining",
                totalPath: "quota.total",
                resetPath: "quota.reset_at"
            )
        ).parse(Data(json.utf8))

        let quota = try #require(snapshot.quotas.first)
        #expect(abs(quota.remainingPercent - 40) < 0.001)
        #expect(quota.resetDate != nil)
    }

    @Test func missingPathThrows() {
        let json = """
        { "data": { "foo": 1 } }
        """
        #expect(throws: (any Error).self) {
            try CustomEndpointProvider(config: config(balancePath: "data.balance"))
                .parse(Data(json.utf8))
        }
    }

    @Test func emptyKeyAllowedForNoAuthCustom() {
        let noAuth = ProviderAccount(
            provider: .custom,
            name: "Public",
            custom: CustomEndpointConfig(endpoint: "https://example.com/a", authStyle: .none)
        )
        #expect(noAuth.allowsEmptyAPIKey)

        let bearer = ProviderAccount(
            provider: .custom,
            name: "Private",
            custom: CustomEndpointConfig(endpoint: "https://example.com/a", authStyle: .bearer)
        )
        #expect(!bearer.allowsEmptyAPIKey)

        #expect(ProviderAccount(provider: .volcengine, name: "Ark").allowsEmptyAPIKey)
        #expect(ProviderAccount(provider: .tencent, name: "Tencent").allowsEmptyAPIKey)
        #expect(!ProviderAccount(provider: .deepseek, name: "DeepSeek").allowsEmptyAPIKey)
    }

    @Test func configRoundTrip() throws {
        let account = ProviderAccount(
            provider: .custom,
            name: "My API",
            custom: CustomEndpointConfig(
                endpoint: "https://example.com/balance",
                authStyle: .raw,
                currency: "CNY",
                balancePath: "data.balance",
                percentPath: "",
                percentIsUsed: false,
                remainingPath: "",
                totalPath: "",
                resetPath: "",
                title: "Custom"
            )
        )
        let data = try JSONEncoder().encode([account])
        let decoded = try JSONDecoder().decode([ProviderAccount].self, from: data)
        #expect(decoded == [account])
        #expect(decoded.first?.custom?.authStyle == .raw)
        #expect(decoded.first?.custom?.balancePath == "data.balance")
    }
}
