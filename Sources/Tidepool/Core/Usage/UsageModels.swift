import Foundation

/// 一条本地会话的用量记录（来自 OpenCode / Claude Code / Codex）。
struct UsageRecord: Identifiable, Equatable, Sendable {
    var id: String
    var date: Date
    /// 归一化后的 provider：deepseek / kimi / glm / 其他原始值
    var provider: String
    var model: String
    var tool: String
    var project: String?
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var costUSD: Double?

    var totalTokens: Int {
        input + output + cacheRead + cacheWrite
    }

    var providerDisplayName: String {
        ProviderLabel.name(for: provider)
    }

    static func canonicalProvider(_ raw: String, model: String = "") -> String {
        let lower = raw.lowercased()
        let modelLower = model.lowercased()
        switch lower {
        case "deepseek": return "deepseek"
        case "kimi", "moonshot": return "kimi"
        case "glm", "zhipu", "bigmodel", "z.ai", "zai": return "glm"
        case "anthropic": return "anthropic"
        case "openai": return "openai"
        default:
            // 聚合渠道（如 tencent / openrouter）按模型名归类
            if modelLower.contains("deepseek") { return "deepseek" }
            if modelLower.contains("kimi") || modelLower.contains("k2") { return "kimi" }
            if modelLower.contains("glm") { return "glm" }
            return lower
        }
    }
}

enum ProviderLabel {
    static func name(for key: String) -> String {
        switch key.lowercased() {
        case "deepseek": return "DeepSeek"
        case "kimi", "moonshot": return "Kimi"
        case "glm", "zhipu", "bigmodel": return "GLM"
        case "anthropic": return "Anthropic"
        case "openai": return "OpenAI"
        case "openrouter": return "OpenRouter"
        case "siliconflow": return "SiliconFlow"
        case "opencode": return "OpenCode"
        default: return key.isEmpty ? T("其他", "Other") : key
        }
    }
}

// MARK: - 聚合

struct ModelUsage: Identifiable, Equatable {
    var id: String { "\(provider)/\(model)" }
    var provider: String
    var model: String
    var tokens: Int
    var cost: Double
    var requests: Int

    var providerName: String {
        ProviderLabel.name(for: provider)
    }
}

struct ToolUsage: Identifiable, Equatable {
    var id: String { tool }
    var tool: String
    var tokens: Int
    var requests: Int
}

struct DailyUsage: Identifiable, Equatable {
    var id: Date { day }
    var day: Date
    var tokens: Int
    var cost: Double
}

struct DailyModelUsage: Identifiable, Equatable {
    var id: String { "\(day.timeIntervalSince1970)-\(model)" }
    var day: Date
    var model: String
    var tokens: Int
}

struct UsageSummary: Equatable {
    var records: [UsageRecord]
    var now: Date

    func records(days: Int) -> [UsageRecord] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return records.filter { $0.date >= cutoff }
    }

    func totalTokens(days: Int) -> Int {
        records(days: days).reduce(0) { $0 + $1.totalTokens }
    }

    func totalCost(days: Int) -> Double {
        records(days: days).reduce(0) { $0 + ($1.costUSD ?? 0) }
    }

    func requests(days: Int) -> Int {
        records(days: days).count
    }

    /// 缓存命中率 = cacheRead / (cacheRead + input)
    func cacheHitRate(days: Int) -> Double? {
        let scoped = records(days: days)
        let read = scoped.reduce(0) { $0 + $1.cacheRead }
        let fresh = scoped.reduce(0) { $0 + $1.input }
        let denominator = read + fresh
        guard denominator > 0 else { return nil }
        return Double(read) / Double(denominator)
    }

    func daily(days: Int) -> [DailyUsage] {
        let calendar = Calendar.current
        let scoped = records(days: days)
        var buckets: [Date: (tokens: Int, cost: Double)] = [:]
        for record in scoped {
            let day = calendar.startOfDay(for: record.date)
            var bucket = buckets[day] ?? (0, 0)
            bucket.tokens += record.totalTokens
            bucket.cost += record.costUSD ?? 0
            buckets[day] = bucket
        }
        // 补齐没有用量的日期，柱状图不会跳
        var result: [DailyUsage] = []
        let today = calendar.startOfDay(for: now)
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let bucket = buckets[day] ?? (0, 0)
            result.append(DailyUsage(day: day, tokens: bucket.tokens, cost: bucket.cost))
        }
        return result
    }

    func dailyModels(days: Int, limit: Int = 5) -> [DailyModelUsage] {
        let scoped = records(days: days)
        let topModels = models(days: days).prefix(limit).map(\.model)
        let calendar = Calendar.current
        var buckets: [String: Int] = [:]
        for record in scoped {
            let day = calendar.startOfDay(for: record.date)
            let label = topModels.contains(record.model) ? record.model : T("其他", "Other")
            let key = "\(day.timeIntervalSince1970)|\(label)"
            buckets[key, default: 0] += record.totalTokens
        }
        return buckets.compactMap { key, tokens in
            let parts = key.split(separator: "|", maxSplits: 1)
            guard let stamp = TimeInterval(parts[0]) else { return nil }
            return DailyModelUsage(
                day: Date(timeIntervalSince1970: stamp),
                model: String(parts[1]),
                tokens: tokens
            )
        }
    }

    func models(days: Int) -> [ModelUsage] {
        let scoped = records(days: days)
        var buckets: [String: ModelUsage] = [:]
        for record in scoped {
            let key = "\(record.provider)/\(record.model)"
            var bucket = buckets[key] ?? ModelUsage(
                provider: record.provider,
                model: record.model,
                tokens: 0,
                cost: 0,
                requests: 0
            )
            bucket.tokens += record.totalTokens
            bucket.cost += record.costUSD ?? 0
            bucket.requests += 1
            buckets[key] = bucket
        }
        return buckets.values.sorted { $0.tokens > $1.tokens }
    }

    func tools(days: Int) -> [ToolUsage] {
        let scoped = records(days: days)
        var buckets: [String: ToolUsage] = [:]
        for record in scoped {
            var bucket = buckets[record.tool] ?? ToolUsage(tool: record.tool, tokens: 0, requests: 0)
            bucket.tokens += record.totalTokens
            bucket.requests += 1
            buckets[record.tool] = bucket
        }
        return buckets.values.sorted { $0.tokens > $1.tokens }
    }

    var activeDays: Int {
        Set(records.map { Calendar.current.startOfDay(for: $0.date) }).count
    }
}
