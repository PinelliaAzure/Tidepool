import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

/// 本地用量明细窗口：趋势、模型拆分、工具来源与 CSV 导出。
struct UsageWindowView: View {
    @Environment(UsageStore.self) private var usageStore
    @Environment(AppStore.self) private var appStore
    @State private var period: Period = .month

    enum Period: CaseIterable, Identifiable {
        case week
        case month
        var id: String { self == .week ? "week" : "month" }
        var days: Int { self == .week ? 7 : 30 }
        var title: String { self == .week ? T("7 天", "7 days") : T("30 天", "30 days") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if usageStore.records.isEmpty {
                emptyState
            } else {
                let summary = usageStore.summary
                metrics(summary)
                chartCard(summary)
                HStack(alignment: .top, spacing: 12) {
                    modelsCard(summary)
                        .frame(maxWidth: .infinity)
                    sourcesCard(summary)
                        .frame(width: 240)
                }
                footer
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(T("本地用量", "Local usage"))
                    .font(.system(size: 20, weight: .semibold))
                Text(T("只读取本机会话文件，不上传任何内容", "Reads local session files only. Nothing is uploaded."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker(T("范围", "Range"), selection: $period) {
                ForEach(Period.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            Button {
                usageStore.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(usageStore.isScanning)
            .help(T("重新扫描本地会话", "Rescan local sessions"))

            Button(T("导出 CSV", "Export CSV")) {
                exportCSV()
            }
            .disabled(usageStore.records.isEmpty)
        }
    }

    // MARK: - 指标

    private func metrics(_ summary: UsageSummary) -> some View {
        let days = period.days
        return HStack(spacing: 10) {
            metricCard(T("总 Tokens", "Total tokens"), value: TideFormatter.tokens(summary.totalTokens(days: days)))
            metricCard(T("估算费用", "Est. cost"), value: costText(summary.totalCost(days: days)))
            metricCard(T("请求数", "Requests"), value: "\(summary.requests(days: days))")
            metricCard(
                T("缓存命中率", "Cache hit rate"),
                value: summary.cacheHitRate(days: days).map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
            )
        }
    }

    private func metricCard(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - 图表

    private func chartCard(_ summary: UsageSummary) -> some View {
        let rows = summary.dailyModels(days: period.days, limit: 5)
        let modelList = summary.models(days: period.days)
        let topModels = modelList.prefix(5).map(\.model)
        let domain = Array(topModels) + (rows.contains { $0.model == T("其他", "Other") } ? [T("其他", "Other")] : [])
        let colors = domain.map { label -> Color in
            if label == T("其他", "Other") { return Color(hex: 0x9CA3AF) }
            let provider = modelList.first(where: { $0.model == label })?.provider ?? ""
            return color(forProvider: provider)
        }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("每日用量", "Daily usage")).sectionHeader()
                Spacer()
                Text(T("按模型堆叠", "Stacked by model"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Chart(rows) { row in
                BarMark(
                    x: .value(T("日期", "Date"), row.day, unit: .day),
                    y: .value("Tokens", row.tokens)
                )
                .foregroundStyle(by: .value(T("模型", "Model"), row.model))
                .cornerRadius(2)
            }
            .chartForegroundStyleScale(domain: domain, range: colors)
            .chartLegend(position: .bottom, spacing: 8)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: period == .week ? 7 : 6)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.05))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(TideFormatter.axisDate(date))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.05))
                    AxisValueLabel {
                        if let tokens = value.as(Int.self) {
                            Text(TideFormatter.tokens(tokens))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .glassCard()
    }

    // MARK: - 模型 / 来源

    private func modelsCard(_ summary: UsageSummary) -> some View {
        let models = Array(summary.models(days: period.days).prefix(8))
        let total = max(1, summary.totalTokens(days: period.days))

        return VStack(alignment: .leading, spacing: 10) {
            Text(T("模型拆分", "Models")).sectionHeader()

            ForEach(Array(models.enumerated()), id: \.element.id) { _, model in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(color(forProvider: model.provider))
                            .frame(width: 6, height: 6)
                        Text(model.model)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                        Text(model.providerName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text(TideFormatter.tokens(model.tokens))
                            .font(.caption.monospacedDigit())
                        Text(costText(model.cost))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.06))
                            Capsule()
                                .fill(color(forProvider: model.provider).opacity(0.65))
                                .frame(width: max(proxy.size.width * CGFloat(model.tokens) / CGFloat(total), 2))
                        }
                    }
                    .frame(height: 3)
                }
            }
        }
        .glassCard()
    }

    private func sourcesCard(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(T("数据来源", "Sources")).sectionHeader()

            ForEach(summary.tools(days: period.days)) { tool in
                HStack {
                    Text(tool.tool)
                        .font(.caption)
                    Spacer()
                    Text(TideFormatter.tokens(tool.tokens))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
                .opacity(0.4)

            VStack(alignment: .leading, spacing: 4) {
                Text(T("扫描路径", "Scanned paths"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("~/.local/share/opencode")
                Text("~/.claude/projects")
                Text("~/.codex/sessions")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        .glassCard()
    }

    // MARK: - 底部 / 空态

    private var footer: some View {
        HStack {
            Text(T("费用为本地估算，仅供参考；OpenCode 使用其自身记录的费用。", "Costs are local estimates; OpenCode costs come from its own records."))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
            if let scan = usageStore.lastScan {
                Text(T("更新于 \(TideFormatter.relative(scan) ?? "")", "Updated \(TideFormatter.relative(scan) ?? "")"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.secondary)
            Text(T("还没有找到本地会话记录", "No local sessions found yet"))
                .font(.headline)
            Text(T("Tidepool 会读取 OpenCode、Claude Code、Codex 的本地会话文件；\n如果你还没用过它们，这里会保持为空。", "Tidepool reads local OpenCode, Claude Code, and Codex sessions.\nIf you haven't used them yet, this stays empty."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(T("立即重新扫描", "Rescan now")) {
                usageStore.refresh()
            }
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 工具

    private func costText(_ value: Double) -> String {
        if appStore.privacyMode { return "•••" }
        guard value > 0 else { return "—" }
        return "≈ " + TideFormatter.usd(value)
    }

    private func color(forProvider provider: String) -> Color {
        switch provider.lowercased() {
        case "deepseek": return Color(hex: 0x4D6BFE)
        case "kimi", "moonshot": return Color(hex: 0x8B5CF6)
        case "glm", "zhipu", "bigmodel": return Color(hex: 0x14B8A6)
        case "anthropic": return Color(hex: 0xD97757)
        case "openai": return Color(hex: 0x10A37F)
        default: return Color(hex: 0x9CA3AF)
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        panel.nameFieldStringValue = "tidepool-usage-\(formatter.string(from: Date())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? UsageCSV.make(records: usageStore.records).write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - 窗口

@MainActor
final class UsageWindowController {
    static let shared = UsageWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = T("Tidepool · 本地用量", "Tidepool · Local usage")
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 720, height: 580)
            window.contentView = NSHostingView(
                rootView: UsageWindowView()
                    .environment(UsageStore.shared)
                    .environment(AppStore.shared)
            )
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
