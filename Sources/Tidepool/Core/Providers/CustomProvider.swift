import Foundation

enum CustomAuthStyle: String, Codable, CaseIterable, Identifiable {
    case bearer
    case raw
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bearer: return T("Bearer Token", "Bearer token")
        case .raw: return T("原始 Token", "Raw token")
        case .none: return T("无鉴权", "No auth")
        }
    }
}

/// 自定义只读接口的配置：任意 JSON + 点路径映射。
struct CustomEndpointConfig: Codable, Equatable {
    var endpoint: String
    var authStyle: CustomAuthStyle
    var currency: String
    var balancePath: String
    var percentPath: String
    var percentIsUsed: Bool
    var remainingPath: String
    var totalPath: String
    var resetPath: String
    var title: String

    init(
        endpoint: String = "",
        authStyle: CustomAuthStyle = .bearer,
        currency: String = "CNY",
        balancePath: String = "",
        percentPath: String = "",
        percentIsUsed: Bool = false,
        remainingPath: String = "",
        totalPath: String = "",
        resetPath: String = "",
        title: String = ""
    ) {
        self.endpoint = endpoint
        self.authStyle = authStyle
        self.currency = currency
        self.balancePath = balancePath
        self.percentPath = percentPath
        self.percentIsUsed = percentIsUsed
        self.remainingPath = remainingPath
        self.totalPath = totalPath
        self.resetPath = resetPath
        self.title = title
    }

    enum CodingKeys: String, CodingKey {
        case endpoint, authStyle, currency, balancePath, percentPath, percentIsUsed
        case remainingPath, totalPath, resetPath, title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        authStyle = try container.decodeIfPresent(CustomAuthStyle.self, forKey: .authStyle) ?? .bearer
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "CNY"
        balancePath = try container.decodeIfPresent(String.self, forKey: .balancePath) ?? ""
        percentPath = try container.decodeIfPresent(String.self, forKey: .percentPath) ?? ""
        percentIsUsed = try container.decodeIfPresent(Bool.self, forKey: .percentIsUsed) ?? false
        remainingPath = try container.decodeIfPresent(String.self, forKey: .remainingPath) ?? ""
        totalPath = try container.decodeIfPresent(String.self, forKey: .totalPath) ?? ""
        resetPath = try container.decodeIfPresent(String.self, forKey: .resetPath) ?? ""
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    }
}

/// 用户自建渠道：GET 一个只读 JSON，用点路径取余额或百分比。
struct CustomEndpointProvider: BalanceProviding {
    let config: CustomEndpointConfig

    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let trimmed = config.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme,
              scheme == "http" || scheme == "https" else {
            throw ProviderError.notSupported(
                T("请填写完整的 endpoint（https://…）", "Enter a full endpoint URL (https://…)")
            )
        }

        let auth: AuthStyle
        switch config.authStyle {
        case .bearer: auth = .bearer
        case .raw: auth = .raw
        case .none: auth = .none
        }

        let data = try await APIClient().getJSON(url: url, apiKey: apiKey, authStyle: auth)
        return try parse(data)
    }

    func parse(_ data: Data) throws -> ProviderSnapshot {
        guard let json = try? JSONSerialization.jsonObject(with: data) else {
            throw ProviderError.network(T("响应不是有效 JSON", "Response is not valid JSON"))
        }

        let plan = config.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? T("自定义", "Custom")
            : config.title
        let resetDate = JSONPath.date(config.resetPath, in: json)

        if let balance = JSONPath.number(config.balancePath, in: json) {
            return ProviderSnapshot(
                fetchedAt: Date(),
                balance: BalanceSnapshot(
                    currency: config.currency.isEmpty ? "CNY" : config.currency,
                    total: balance,
                    granted: nil,
                    toppedUp: nil,
                    isAvailable: balance > 0
                ),
                quotas: [],
                planName: plan
            )
        }

        var remainingPercent: Double?
        if let remaining = JSONPath.number(config.remainingPath, in: json),
           let total = JSONPath.number(config.totalPath, in: json),
           total > 0 {
            remainingPercent = remaining / total * 100
        } else if let percent = JSONPath.number(config.percentPath, in: json) {
            remainingPercent = config.percentIsUsed ? 100 - percent : percent
        }

        guard let remainingPercent else {
            throw ProviderError.notSupported(
                T(
                    "没有匹配到配置的 JSON 路径，请检查「余额路径 / 百分比路径」",
                    "No configured JSON path matched. Check the balance or percent path."
                )
            )
        }

        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: nil,
            quotas: [
                QuotaWindow(
                    kind: .custom,
                    remainingPercent: min(max(remainingPercent, 0), 100),
                    resetDate: resetDate
                )
            ],
            planName: plan
        )
    }
}

// MARK: - 点路径

enum JSONPath {
    static func value(_ path: String, in root: Any) -> Any? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var current: Any? = root
        for part in trimmed.split(separator: ".") {
            if let index = Int(part), let array = current as? [Any] {
                guard array.indices.contains(index) else { return nil }
                current = array[index]
            } else if let dictionary = current as? [String: Any] {
                current = dictionary[String(part)]
            } else {
                return nil
            }
        }
        return current
    }

    static func number(_ path: String, in root: Any) -> Double? {
        guard let raw = value(path, in: root) else { return nil }
        if let number = raw as? NSNumber { return number.doubleValue }
        if let string = raw as? String { return Double(string) }
        return nil
    }

    static func date(_ path: String, in root: Any) -> Date? {
        guard let raw = value(path, in: root) else { return nil }
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            if value > 1_000_000_000_000 { return Date(timeIntervalSince1970: value / 1000) }
            if value > 1_000_000_000 { return Date(timeIntervalSince1970: value) }
            return nil
        }
        if let string = raw as? String {
            if let value = Double(string) {
                if value > 1_000_000_000_000 { return Date(timeIntervalSince1970: value / 1000) }
                if value > 1_000_000_000 { return Date(timeIntervalSince1970: value) }
            }
            return ISO8601Date.parse(string)
        }
        return nil
    }
}
