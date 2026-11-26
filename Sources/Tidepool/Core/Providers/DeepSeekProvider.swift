import Foundation

/// DeepSeek 开放平台余额（官方文档接口，只读、不消耗额度）。
/// GET https://api.deepseek.com/user/balance
struct DeepSeekProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let base = baseURL ?? URL(string: "https://api.deepseek.com")!
        let data = try await APIClient().getJSON(
            url: base.appendingPathComponent("user/balance"),
            apiKey: apiKey
        )
        return try parse(data)
    }

    func parse(_ data: Data) throws -> ProviderSnapshot {
        let response = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
        guard let info = response.balanceInfos?.first else {
            throw ProviderError.http(200)
        }
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: info.currency,
                total: Double(info.totalBalance) ?? 0,
                granted: Double(info.grantedBalance ?? "0"),
                toppedUp: Double(info.toppedUpBalance ?? "0"),
                isAvailable: response.isAvailable ?? true
            ),
            quotas: [],
            planName: nil
        )
    }
}

private struct DeepSeekBalanceResponse: Decodable {
    let isAvailable: Bool?
    let balanceInfos: [BalanceInfo]?

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String
        // 官方文档未保证这两个字段始终存在，缺失时按 0 处理。
        let grantedBalance: String?
        let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }
}
