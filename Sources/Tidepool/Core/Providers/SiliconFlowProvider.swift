import Foundation

/// 硅基流动（SiliconFlow）账户余额。
/// 国内站 `GET https://api.siliconflow.cn/v1/user/info` 已于 2026-08-14 下线（HTTP 410）；
/// 国际站 `GET https://api.siliconflow.com/v1/user/info` 仍可用，余额以 USD 计。
struct SiliconFlowProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let base = baseURL ?? URL(string: "https://api.siliconflow.cn")!
        do {
            let data = try await APIClient().getJSON(
                url: base.appendingPathComponent("v1/user/info"),
                apiKey: apiKey
            )
            return try parse(data, currency: currency(for: base))
        } catch ProviderError.http(410) {
            throw Self.retiredError
        }
    }

    func parse(_ data: Data, currency: String = "CNY") throws -> ProviderSnapshot {
        let response = try JSONDecoder().decode(SiliconFlowUserResponse.self, from: data)
        if response.code == 20092 {
            throw Self.retiredError
        }
        guard let payload = response.data else {
            throw ProviderError.http(200)
        }
        let total = payload.totalBalance?.value ?? payload.balance?.value ?? 0
        let toppedUp = payload.chargeBalance?.value
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: BalanceSnapshot(
                currency: currency,
                total: total,
                granted: nil,
                toppedUp: toppedUp,
                isAvailable: total > 0
            ),
            quotas: [],
            planName: "SiliconFlow"
        )
    }

    private func currency(for base: URL) -> String {
        base.host?.contains("siliconflow.com") == true ? "USD" : "CNY"
    }

    static var retiredError: ProviderError {
        .notSupported(
            T(
                "硅基流动国内站余额接口已于 2026-08-14 下线，这不是 API Key 无效。请到 cloud.siliconflow.cn 查看余额；国际站账号可在设置里切换到 api.siliconflow.com（USD）。",
                "SiliconFlow retired its China balance API on 2026-08-14; your API key is not invalid. Check the balance at cloud.siliconflow.cn, or switch to api.siliconflow.com (USD) for an international account."
            )
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
