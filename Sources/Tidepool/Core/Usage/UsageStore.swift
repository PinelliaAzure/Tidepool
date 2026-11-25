import Foundation
import Observation

/// 本地用量中心：启动时扫描一次，之后每 10 分钟刷新。
/// 只读本机文件，不上传任何内容。
@MainActor
@Observable
final class UsageStore {
    static let shared = UsageStore()

    private(set) var records: [UsageRecord] = []
    private(set) var lastScan: Date?
    private(set) var isScanning = false
    private(set) var toolsFound: [String] = []
    private(set) var enabled: Bool

    var onChanged: (() -> Void)?

    private var timer: Timer?
    private let lookbackDays = 30

    private init() {
        enabled = Prefs.usageScanEnabled
    }

    var summary: UsageSummary {
        UsageSummary(records: records, now: Date())
    }

    func start() {
        guard enabled else { return }
        refresh()
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func setEnabled(_ isEnabled: Bool) {
        enabled = isEnabled
        Prefs.usageScanEnabled = isEnabled
        if isEnabled {
            start()
        } else {
            stopTimer()
            records = []
            toolsFound = []
            isScanning = false
            onChanged?()
        }
    }

    func refresh() {
        guard enabled, !isScanning else { return }
        isScanning = true
        let since = Date().addingTimeInterval(-Double(lookbackDays) * 86_400)

        Task.detached(priority: .utility) {
            var collected: [UsageRecord] = []
            var tools: Set<String> = []

            let openCode = OpenCodeUsageScanner().scan(since: since)
            if !openCode.isEmpty {
                collected.append(contentsOf: openCode)
                tools.insert("OpenCode")
            }
            let claude = ClaudeUsageScanner().scan(since: since)
            if !claude.isEmpty {
                collected.append(contentsOf: claude)
                tools.insert("Claude Code")
            }
            let codex = CodexUsageScanner().scan(since: since)
            if !codex.isEmpty {
                collected.append(contentsOf: codex)
                tools.insert("Codex")
            }

            let sorted = collected.sorted { $0.date > $1.date }
            let found = tools.sorted()

            await MainActor.run {
                self.records = sorted
                self.toolsFound = found
                self.lastScan = Date()
                self.isScanning = false
                self.onChanged?()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

#if DEBUG
    /// `--preview` 用的假用量。
    func seedPreviewData() {
        guard records.isEmpty else { return }
        let now = Date()
        var seeded: [UsageRecord] = []
        let models = [
            ("deepseek", "deepseek-flash", 0.42),
            ("kimi", "kimi-k2", 0.18),
            ("glm", "glm-5.3", 0.06)
        ]
        for dayOffset in 0..<8 {
            for (index, spec) in models.enumerated() {
                let count = 6 + (dayOffset * 3 + index * 2) % 7
                for request in 0..<count {
                    let date = Calendar.current.date(
                        byAdding: .hour,
                        value: -(dayOffset * 24 + request * 3),
                        to: now
                    ) ?? now
                    let input = 4_000 + (request * 1_700) % 9_000
                    let output = 600 + (request * 240) % 1_800
                    let cacheRead = (index == 0 ? 240_000 : 40_000) + request * 2_000
                    seeded.append(
                        UsageRecord(
                            id: "preview-\(dayOffset)-\(index)-\(request)",
                            date: date,
                            provider: spec.0,
                            model: spec.1,
                            tool: index == 0 ? "OpenCode" : (index == 1 ? "Claude Code" : "Codex"),
                            project: index == 0 ? "Tidepool" : (index == 1 ? "quant-desk" : "invoice-tool"),
                            input: input,
                            output: output,
                            cacheRead: cacheRead,
                            cacheWrite: 0,
                            costUSD: spec.2 * Double(request + 1) / 8
                        )
                    )
                }
            }
        }
        records = seeded.sorted { $0.date > $1.date }
        toolsFound = ["Claude Code", "Codex", "OpenCode"]
        lastScan = now
    }
#endif
}

// MARK: - CSV

enum UsageCSV {
    static func make(records: [UsageRecord]) -> String {
        var lines: [String] = [
            "date,tool,provider,model,project,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,total_tokens,cost_usd"
        ]
        let formatter = ISO8601DateFormatter()
        for record in records.sorted(by: { $0.date < $1.date }) {
            let fields: [String] = [
                formatter.string(from: record.date),
                record.tool,
                record.providerDisplayName,
                record.model,
                record.project ?? "",
                String(record.input),
                String(record.output),
                String(record.cacheRead),
                String(record.cacheWrite),
                String(record.totalTokens),
                record.costUSD.map { String(format: "%.6f", $0) } ?? ""
            ]
            lines.append(fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
