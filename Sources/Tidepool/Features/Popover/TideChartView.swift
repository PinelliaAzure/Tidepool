import Charts
import SwiftUI

/// 余额水位图：渐变面积图；7 天 / 30 天两个范围。
struct TideChartView: View {
    let account: ProviderAccount
    @Environment(AppStore.self) private var store
    @State private var chartRange: ChartRange = .week

    enum ChartRange: String, CaseIterable, Identifiable {
        case week = "7 天"
        case month = "30 天"

        var id: String { rawValue }
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("水位").sectionHeader()
                Spacer()
                Picker("范围", selection: $chartRange) {
                    ForEach(ChartRange.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
            }
            chartContent
        }
        .glassCard()
    }

    @ViewBuilder
    private var chartContent: some View {
        let samples = visibleSamples
        if samples.count < 2 {
            Text("正在积累潮汐数据…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 46)
        } else {
            Chart(samples) { sample in
                AreaMark(
                    x: .value("时间", sample.date),
                    y: .value("余额", sample.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [accent.opacity(0.32), accent.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                LineMark(
                    x: .value("时间", sample.date),
                    y: .value("余额", sample.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date, format: .dateTime.month().day())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let amount = value.as(Double.self) {
                            Text(
                                store.privacyMode
                                    ? "•••"
                                    : TideFormatter.money(amount, currency: currencyCode, style: .axis)
                            )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(height: 116)
        }
    }

    private var visibleSamples: [SamplePoint] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(chartRange.days * 86_400))
        return store.samples(for: account.id).filter { $0.date >= cutoff }
    }

    private var accent: Color {
        account.provider.brandColor
    }

    private var currencyCode: String {
        store.snapshots[account.id]?.balance?.currency ?? "CNY"
    }
}
