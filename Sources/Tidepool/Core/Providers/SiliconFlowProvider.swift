import Foundation

/// 硅基流动（SiliconFlow）账户余额（CNY）。
/// GET https://api.siliconflow.cn/v1/user/info
struct SiliconFlowProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let base = baseURL ?? URL(string: "https://api.siliconflow.cn")!
        let data = try await APIClient().getJSON(
            url: base.appendingPathComponent("v1/user/info"),
            apiKey: apiKey
        )
        return try parse(data)
    }

    func parse(_ data: Data) throws -> ProviderSnapshot {
        let response = try JSONDecoder().decode(SiliconFlowUserResponse.self, from: data)
        guard let payload = response.data else {
            throw ProviderError.http(200)
        }
        let total = payload.totalBalance?.value ?? payload.balance?.value ?? 0
        let toppedUp = payload.chargeBalance?.value
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: "CNY",
                total: total,
                granted: nil,
                toppedUp: toppedUp,
                isAvailable: total > 0
            ),
            quotas: [],
            planName: "SiliconFlow"
        )
    }
}

private struct SiliconFlowUserResponse: Decodable {
    struct Payload: Decodable {
        let balance: FlexDouble?
        let chargeBalance: FlexDouble?
        let totalBalance: FlexDouble?

        enum CodingKeys: String, CodingKey {
            case balance
            case chargeBalance
            case totalBalance
        }
    }

    let code: Int?
    let status: Bool?
    let data: Payload?
}

/// 接口里的金额既可能是数字也可能是字符串。
private struct FlexDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text)
        } else {
            value = nil
        }
    }
}
