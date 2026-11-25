import Foundation

/// 简易价格表（USD / 1M tokens），仅用于给没有自带费用的本地会话做估算。
/// 价格会变，界面统一标注「估算」；OpenCode 自带 cost 时优先用真实值。
enum Pricing {
    struct Rate {
        var input: Double
        var output: Double
        var cacheRead: Double
        var cacheWrite: Double
    }

    static func rate(provider: String, model: String) -> Rate? {
        let name = model.lowercased()
        switch provider.lowercased() {
        case "anthropic":
            if name.contains("opus") {
                return Rate(input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75)
            }
            if name.contains("haiku") {
                return Rate(input: 0.8, output: 4, cacheRead: 0.08, cacheWrite: 1)
            }
            if name.contains("sonnet") {
                return Rate(input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75)
            }
        case "openai":
            if name.contains("gpt-5") {
                return Rate(input: 1.25, output: 10, cacheRead: 0.125, cacheWrite: 1.25)
            }
            if name.contains("gpt-4.1") || name.contains("gpt-4o") {
                return Rate(input: 2.5, output: 10, cacheRead: 1.25, cacheWrite: 2.5)
            }
            if name.contains("o4") || name.contains("o3") {
                return Rate(input: 2, output: 8, cacheRead: 0.5, cacheWrite: 2)
            }
        case "deepseek":
            if name.contains("reasoner") {
                return Rate(input: 0.28, output: 0.42, cacheRead: 0.028, cacheWrite: 0.28)
            }
            if name.contains("deepseek") {
                return Rate(input: 0.28, output: 0.42, cacheRead: 0.028, cacheWrite: 0.28)
            }
        case "kimi":
            if name.contains("kimi") || name.contains("k2") {
                return Rate(input: 0.6, output: 2.5, cacheRead: 0.15, cacheWrite: 0.6)
            }
        case "glm":
            if name.contains("glm") {
                return Rate(input: 0.6, output: 2.2, cacheRead: 0.11, cacheWrite: 0.6)
            }
        default:
            break
        }
        return nil
    }

    static func estimate(
        provider: String,
        model: String,
        input: Int,
        output: Int,
        cacheRead: Int,
        cacheWrite: Int
    ) -> Double? {
        guard let rate = rate(provider: provider, model: model) else { return nil }
        let million = 1_000_000.0
        return Double(input) / million * rate.input
            + Double(output) / million * rate.output
            + Double(cacheRead) / million * rate.cacheRead
            + Double(cacheWrite) / million * rate.cacheWrite
    }
}
