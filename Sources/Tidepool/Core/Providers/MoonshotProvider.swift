import Foundation

/// Kimi / Moonshot 开放平台余额（官方文档接口）。
/// GET https://api.moonshot.cn/v1/users/me/balance （国际站：api.moonshot.ai）
struct MoonshotProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let base = baseURL ?? URL(string: "https://api.moonshot.cn")!
        let data = try await APIClient().getJSON(
            url: base.appendingPathComponent("v1/users/me/balance"),
            apiKey: apiKey
        )
        return try parse(data)
    }

    func parse(_ data: Data) throws -> ProviderSnapshot {
        let response = try JSONDecoder().decode(MoonshotBalanceResponse.self, from: data)
        guard let payload = response.data else {
            throw ProviderError.http(200)
        }
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: "CNY",
                total: payload.availableBalance,
                granted: payload.voucherBalance,
                toppedUp: payload.cashBalance,
                isAvailable: payload.availableBalance > 0
            ),
            quotas: [],
            planName: nil
        )
    }
}

private struct MoonshotBalanceResponse: Decodable {
    let code: Int?
    let status: Bool?
    let data: Payload?

    struct Payload: Decodable {
        let availableBalance: Double
        let voucherBalance: Double
        let cashBalance: Double

        enum CodingKeys: String, CodingKey {
            case availableBalance = "available_balance"
            case voucherBalance = "voucher_balance"
            case cashBalance = "cash_balance"
        }
    }
}
