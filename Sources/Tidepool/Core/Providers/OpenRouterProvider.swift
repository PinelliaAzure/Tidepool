import Foundation

/// OpenRouter 账户额度（USD）。
/// GET https://openrouter.ai/api/v1/credits
struct OpenRouterProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let base = baseURL ?? URL(string: "https://openrouter.ai")!
        let data = try await APIClient().getJSON(
            url: base.appendingPathComponent("api/v1/credits"),
            apiKey: apiKey
        )
        return try parse(data)
    }

    func parse(_ data: Data) throws -> ProviderSnapshot {
        let response = try JSONDecoder().decode(OpenRouterCreditsResponse.self, from: data)
        guard let payload = response.data else {
            throw ProviderError.http(200)
        }
        let remaining = max(0, payload.totalCredits - payload.totalUsage)
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: "USD",
                total: remaining,
                granted: nil,
                toppedUp: payload.totalCredits,
                isAvailable: remaining > 0
            ),
            quotas: [],
            planName: "OpenRouter"
        )
    }
}

private struct OpenRouterCreditsResponse: Decodable {
    struct Payload: Decodable {
        let totalCredits: Double
        let totalUsage: Double

        enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }

    let data: Payload?
}
