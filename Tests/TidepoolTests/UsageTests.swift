import Foundation
import Testing
@testable import Tidepool

@Suite("本地用量扫描与聚合")
struct UsageTests {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidepool-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func recentTimestamp(minutesAgo: Int = 30) -> String {
        let date = Date().addingTimeInterval(-Double(minutesAgo) * 60)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    @Test func claudeFixture() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let json = """
        {"type":"assistant","timestamp":"\(recentTimestamp())","cwd":"/Users/x/proj","message":{"model":"claude-sonnet-4-5","usage":{"input_tokens":1000,"output_tokens":200,"cache_read_input_tokens":5000,"cache_creation_input_tokens":300}}}
        """
        try json.write(
            to: root.appendingPathComponent("session.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let records = ClaudeUsageScanner(root: root.path).scan(since: Date().addingTimeInterval(-3600))
        #expect(records.count == 1)

        let record = try #require(records.first)
        #expect(record.tool == "Claude Code")
        #expect(record.provider == "anthropic")
        #expect(record.model == "claude-sonnet-4-5")
        #expect(record.project == "proj")
        #expect(record.input == 1000)
        #expect(record.output == 200)
        #expect(record.cacheRead == 5000)
        #expect(record.cacheWrite == 300)
        #expect((record.costUSD ?? 0) > 0)
    }

    @Test func codexFixture() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let stamp = recentTimestamp()
        let lines = [
            #"{"timestamp":"\#(stamp)","type":"session_meta","payload":{"cwd":"/Users/x/codexproj"}}"#,
            #"{"timestamp":"\#(stamp)","type":"turn_context","payload":{"model":"gpt-5-codex"}}"#,
            #"{"timestamp":"\#(stamp)","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":2000,"cached_input_tokens":1500,"output_tokens":300,"reasoning_output_tokens":100}}}}"#
        ]
        try lines.joined(separator: "\n").write(
            to: root.appendingPathComponent("rollout.jsonl"),
            atomically: true,
            encoding: .utf8
        )

        let records = CodexUsageScanner(root: root.path).scan(since: Date().addingTimeInterval(-3600))
        #expect(records.count == 1)

        let record = try #require(records.first)
        #expect(record.tool == "Codex")
        #expect(record.provider == "openai")
        #expect(record.model == "gpt-5-codex")
        #expect(record.project == "codexproj")
        #expect(record.input == 500)
        #expect(record.output == 400)
        #expect(record.cacheRead == 1500)
    }

    @Test func providerNormalization() {
        #expect(UsageRecord.canonicalProvider("tencent", model: "glm-5.3") == "glm")
        #expect(UsageRecord.canonicalProvider("openrouter", model: "deepseek-chat") == "deepseek")
        #expect(UsageRecord.canonicalProvider("moonshot", model: "kimi-k2") == "kimi")
        #expect(UsageRecord.canonicalProvider("opencode", model: "big-pickle") == "opencode")
    }

    @Test func aggregation() {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let records = [
            UsageRecord(
                id: "1", date: today.addingTimeInterval(3600), provider: "deepseek",
                model: "deepseek-flash", tool: "OpenCode", project: "a",
                input: 1000, output: 500, cacheRead: 2000, cacheWrite: 0, costUSD: 0.1
            ),
            UsageRecord(
                id: "2", date: yesterday.addingTimeInterval(3600), provider: "deepseek",
                model: "deepseek-flash", tool: "OpenCode", project: "a",
                input: 1000, output: 500, cacheRead: 0, cacheWrite: 0, costUSD: 0.2
            ),
            UsageRecord(
                id: "3", date: yesterday.addingTimeInterval(7200), provider: "glm",
                model: "glm-5.3", tool: "OpenCode", project: "b",
                input: 4000, output: 1000, cacheRead: 0, cacheWrite: 0, costUSD: nil
            )
        ]
        let summary = UsageSummary(records: records, now: now)

        #expect(summary.totalTokens(days: 7) == 10_000)
        #expect(abs(summary.totalCost(days: 7) - 0.3) < 0.0001)
        #expect(summary.requests(days: 7) == 3)

        let daily = summary.daily(days: 3)
        #expect(daily.count == 3)
        #expect(daily.last?.tokens == 3500)

        let models = summary.models(days: 7)
        #expect(models.count == 2)
        #expect(models.contains { $0.model == "glm-5.3" && $0.tokens == 5000 })
        #expect(models.contains { $0.model == "deepseek-flash" && $0.tokens == 5000 })

        // cacheRead 2000 / (cacheRead 2000 + input 6000) = 0.25
        #expect(abs((summary.cacheHitRate(days: 7) ?? 0) - 0.25) < 0.0001)
    }

    @Test func csvEscaping() {
        let record = UsageRecord(
            id: "1", date: Date(timeIntervalSince1970: 1_800_000_000),
            provider: "deepseek", model: "deepseek-chat", tool: "OpenCode",
            project: "a,b\"c", input: 10, output: 20, cacheRead: 0, cacheWrite: 0, costUSD: 0.001
        )
        let csv = UsageCSV.make(records: [record])
        #expect(csv.contains("\"a,b\"\"c\""))
        #expect(csv.contains("deepseek-chat"))
        #expect(csv.hasPrefix("date,tool,provider,model,project"))
    }

    @Test func tokenFormatting() {
        #expect(TideFormatter.tokens(932) == "932")
        #expect(TideFormatter.tokens(86_200) == "86.2k")
        #expect(TideFormatter.tokens(5_642_036) == "5.64M")
        #expect(TideFormatter.usd(0.004) == "<$0.01")
        #expect(TideFormatter.usd(1.239) == "$1.24")
    }
}
