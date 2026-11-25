import Foundation

/// Kimi For Coding 套餐额度（非公开只读接口，多项目在用；返回结构可能变化）。
/// GET https://api.kimi.com/coding/v1/usages
struct KimiCodeProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let base = baseURL ?? ProviderID.kimiCode.defaultBaseURL
        let data = try await APIClient().getJSON(
            url: base.appendingPathComponent("coding/v1/usages"),
            apiKey: apiKey
        )
        return try parse(data)
    }

    func parse(_ data: Data) throws -> ProviderSnapshot {
        let response = try JSONDecoder().decode(KimiUsageResponse.self, from: data)

        var quotas: [QuotaWindow] = []
        let fiveHour = response.usages?["limit_5h"]
        let weeklyFallback = response.usages?["limit_7d"]

        var weeklyReset = weeklyFallback?.resetTime.flatMap(ISO8601Date.parse)

        if let usage = response.usage {
            let limit = Double(usage.limit ?? "") ?? 0
            let used = Double(usage.used ?? "") ?? 0
            let remaining = Double(usage.remaining ?? "") ?? max(0, limit - used)
            if limit > 0 {
                let pct = min(max(remaining / limit * 100, 0), 100)
                weeklyReset = ISO8601Date.parse(usage.resetTime) ?? weeklyReset
                quotas.append(QuotaWindow(kind: .weekly, remainingPercent: pct, resetDate: weeklyReset))
            }
        } else if let weekly = weeklyFallback, let ratio = weekly.usedRatio {
            quotas.append(
                QuotaWindow(
                    kind: .weekly,
                    remainingPercent: min(max((1 - ratio) * 100, 0), 100),
                    resetDate: weeklyReset
                )
            )
        }

        if let fiveHour, let ratio = fiveHour.usedRatio {
            quotas.append(
                QuotaWindow(
                    kind: .fiveHour,
                    remainingPercent: min(max((1 - ratio) * 100, 0), 100),
                    resetDate: fiveHour.resetTime.flatMap(ISO8601Date.parse)
                )
            )
        }

        guard !quotas.isEmpty else {
            throw ProviderError.notSupported("该 Key 没有可读取的 Kimi Code 套餐额度")
        }

        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: nil,
            quotas: quotas.sorted { $0.kind.sortOrder < $1.kind.sortOrder },
            planName: "Kimi Code"
        )
    }
}

private struct KimiUsageResponse: Decodable {
    struct Summary: Decodable {
        let limit: String?
        let used: String?
        let remaining: String?
        let resetTime: String?

        enum CodingKeys: String, CodingKey {
            case limit, used, remaining
            case resetTime = "resetTime"
        }
    }

    struct Window: Decodable {
        let usedRatio: Double?
        let resetTime: String?

        enum CodingKeys: String, CodingKey {
            case usedRatio = "used_ratio"
            case resetTime = "reset_time"
        }
    }

    let usage: Summary?
    let usages: [String: Window]?
}

// MARK: - 日期解析

enum ISO8601Date {
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string else { return nil }
        return fractional.date(from: string) ?? plain.date(from: string)
    }
}
