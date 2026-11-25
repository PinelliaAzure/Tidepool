import Foundation

/// Codex CLI 的本地会话：`~/.codex/sessions/**/*.jsonl`。
/// 逐行读取 turn_context（模型、cwd）与 token_count（last_token_usage）。
struct CodexUsageScanner {
    var root: String = ("~/.codex/sessions" as NSString).expandingTildeInPath

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
        var model = "unknown"
        var project: String?
        var index = 0

        for line in content.split(separator: "\n") {
            guard line.contains("turn_context") || line.contains("token_count") || line.contains("session_meta") else {
                continue
            }
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = object["payload"] as? [String: Any] else { continue }

            if let cwd = payload["cwd"] as? String {
                project = URL(fileURLWithPath: cwd).lastPathComponent
            }
            if let modelName = payload["model"] as? String, !modelName.isEmpty {
                model = modelName
            }

            guard payload["type"] as? String == "token_count" else { continue }
            guard let info = payload["info"] as? [String: Any] else { continue }
            guard let last = info["last_token_usage"] as? [String: Any] else { continue }

            let timestamp = ISO8601Date.parse(object["timestamp"] as? String) ?? Date()
            guard timestamp >= since else { continue }

            let input = intValue(last["input_tokens"])
            let cached = intValue(last["cached_input_tokens"])
            let output = intValue(last["output_tokens"])
            let reasoning = intValue(last["reasoning_output_tokens"])
            guard input + cached + output + reasoning > 0 else { continue }

            let provider = UsageRecord.canonicalProvider("openai", model: model)
            let freshInput = max(0, input - cached)
            records.append(
                UsageRecord(
                    id: "codex-\(file.lastPathComponent)-\(index)",
                    date: timestamp,
                    provider: provider,
                    model: model,
                    tool: "Codex",
                    project: project,
                    input: freshInput,
                    output: output + reasoning,
                    cacheRead: cached,
                    cacheWrite: 0,
                    costUSD: Pricing.estimate(
                        provider: provider,
                        model: model,
                        input: freshInput,
                        output: output + reasoning,
                        cacheRead: cached,
                        cacheWrite: 0
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
