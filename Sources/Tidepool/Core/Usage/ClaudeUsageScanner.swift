import Foundation

/// Claude Code 的本地会话：`~/.claude/projects/**/*.jsonl`，
/// 每行 assistant 消息带 `message.usage` 与 model。
struct ClaudeUsageScanner {
    var root: String = ("~/.claude/projects" as NSString).expandingTildeInPath

    func scan(since: Date) -> [UsageRecord] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var records: [UsageRecord] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  let modified = values.contentModificationDate,
                  modified >= since else { continue }
            records.append(contentsOf: parse(file: url, since: since))
        }
        return records
    }

    private func parse(file: URL, since: Date) -> [UsageRecord] {
        guard let content = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        var records: [UsageRecord] = []
        var index = 0

        for line in content.split(separator: "\n") {
            guard line.contains("\"usage\""), line.contains("assistant") else { continue }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String == "assistant",
                  let message = object["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }

            let timestamp = ISO8601Date.parse(object["timestamp"] as? String) ?? Date()
            guard timestamp >= since else { continue }

            let model = message["model"] as? String ?? "unknown"
            let input = intValue(usage["input_tokens"])
            let output = intValue(usage["output_tokens"])
            let cacheRead = intValue(usage["cache_read_input_tokens"])
            let cacheWrite = intValue(usage["cache_creation_input_tokens"])
            guard input + output + cacheRead + cacheWrite > 0 else { continue }

            let cwd = object["cwd"] as? String
            let provider = UsageRecord.canonicalProvider("anthropic", model: model)
            records.append(
                UsageRecord(
                    id: "claude-\(file.lastPathComponent)-\(index)",
                    date: timestamp,
                    provider: provider,
                    model: model,
                    tool: "Claude Code",
                    project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
                    input: input,
                    output: output,
                    cacheRead: cacheRead,
                    cacheWrite: cacheWrite,
                    costUSD: Pricing.estimate(
                        provider: provider,
                        model: model,
                        input: input,
                        output: output,
                        cacheRead: cacheRead,
                        cacheWrite: cacheWrite
                    )
                )
            )
            index += 1
        }
        return records
    }

    private func intValue(_ raw: Any?) -> Int {
        if let value = raw as? Int { return value }
        if let value = raw as? Double { return Int(value) }
        if let value = raw as? String { return Int(value) ?? 0 }
        return 0
    }
}
