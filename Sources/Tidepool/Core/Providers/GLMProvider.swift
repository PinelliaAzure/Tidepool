import Foundation

/// GLM Coding Plan 额度（非公开只读接口；CN 站鉴权是原始 token，Z.ai 是 Bearer，两种都试）。
/// GET https://open.bigmodel.cn/api/monitor/usage/quota/limit
/// GET https://api.z.ai/api/monitor/usage/quota/limit
struct GLMProvider: BalanceProviding {
    func fetch(apiKey: String, baseURL: URL?) async throws -> ProviderSnapshot {
        let base = baseURL ?? ProviderID.glm.defaultBaseURL
        let url = base.appendingPathComponent("api/monitor/usage/quota/limit")
        let client = APIClient()

        // 智谱 CN 站接受原始 token，Z.ai 走 Bearer；按站点优先，另一种作为兜底。
        let preferRaw = base.host?.contains("bigmodel.cn") == true
        let styles: [AuthStyle] = preferRaw ? [.raw, .bearer] : [.bearer, .raw]
        var lastError: Error = ProviderError.invalidKey

        for style in styles {
            do {
                let data = try await client.getJSON(url: url, apiKey: apiKey, authStyle: style)
                return try parse(data)
            } catch ProviderError.invalidKey {
                lastError = ProviderError.invalidKey
                continue
            }
        }
        throw lastError
    }

    func parse(_ data: Data) throws -> ProviderSnapshot {
        let response = try JSONDecoder().decode(GLMQuotaResponse.self, from: data)
        if response.success == false {
            if let message = response.msg, message.lowercased().contains("coding plan") {
                throw ProviderError.notSupported("该 Key 没有有效的 GLM Coding Plan")
            }
            throw ProviderError.invalidKey
        }
        guard let payload = response.data, let limits = payload.limits, !limits.isEmpty else {
            throw ProviderError.notSupported("该 Key 没有可读取的 GLM Coding Plan 额度")
        }

        // unit=3：5 小时窗口；unit=6：周额度；TIME_LIMIT：网页工具（MCP）月度额度
        let tokenLimits = limits.filter { $0.type == "TOKENS_LIMIT" }
        let fiveHour = tokenLimits.first { $0.unit == 3 }
        let weekly = tokenLimits.first { $0.unit == 6 }
        let mcp = limits.first { $0.type == "TIME_LIMIT" }

        var quotas: [QuotaWindow] = []

        if let weekly, let usedPct = weekly.percentage {
            quotas.append(
                QuotaWindow(
                    kind: .weekly,
                    remainingPercent: clampRemaining(100 - Double(usedPct)),
                    resetDate: dateFromMillis(weekly.nextResetTime)
                )
            )
        }
        if let fiveHour, let usedPct = fiveHour.percentage {
            quotas.append(
                QuotaWindow(
                    kind: .fiveHour,
                    remainingPercent: clampRemaining(100 - Double(usedPct)),
                    resetDate: dateFromMillis(fiveHour.nextResetTime)
                )
            )
        }
        if let mcp, let total = mcp.usage, total > 0 {
            let used = mcp.currentValue ?? 0
            let remaining = mcp.remaining ?? max(0, total - used)
            quotas.append(
                QuotaWindow(
                    kind: .monthly,
                    remainingPercent: clampRemaining(Double(remaining) / Double(total) * 100),
                    resetDate: dateFromMillis(mcp.nextResetTime)
                )
            )
        }

        guard !quotas.isEmpty else {
            throw ProviderError.notSupported("该 Key 没有可读取的 GLM Coding Plan 额度")
        }

        let level = payload.level.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return ProviderSnapshot(
            fetchedAt: Date(),
            balance: nil,
            quotas: quotas.sorted { $0.kind.sortOrder < $1.kind.sortOrder },
            planName: level.map { "GLM Coding Plan · \($0)" } ?? "GLM Coding Plan"
        )
    }

    private func clampRemaining(_ value: Double) -> Double {
        min(max(value, 0), 100)
    }

    private func dateFromMillis(_ millis: Int64?) -> Date? {
        guard let millis else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(millis) / 1000)
    }
}

private struct GLMQuotaResponse: Decodable {
    struct Payload: Decodable {
        let limits: [Limit]?
        let level: String?
    }

    struct Limit: Decodable {
        let type: String
        let unit: Int?
        let percentage: Int?
        let usage: Int?
        let currentValue: Int?
        let remaining: Int?
        let nextResetTime: Int64?
    }

    let code: Int?
    let success: Bool?
    let msg: String?
    let data: Payload?
}
