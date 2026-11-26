import Charts
import SwiftUI

/// 余额水位图：渐变面积图；7 天 / 30 天两个范围。
struct TideChartView: View {
    let account: ProviderAccount
    @Environment(AppStore.self) private var store
    @State private var chartRange: ChartRange = .week

    enum ChartRange: CaseIterable, Identifiable {
        case week
        case month

        var id: String { self == .week ? "week" : "month" }
        var days: Int { self == .week ? 7 : 30 }
        var title: String { self == .week ? T("7 天", "7 days") : T("30 天", "30 days") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(T("水位", "Water level")).sectionHeader()
                Spacer()
                Picker(T("范围", "Range"), selection: $chartRange) {
                    ForEach(ChartRange.allCases) { option in
                        Text(option.title).tag(option)
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
            Text(T("正在积累潮汐数据…", "Collecting tide data…"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 46)
        } else {
            Chart(samples) { sample in
                AreaMark(
                    x: .value(T("时间", "Time"), sample.date),
                    y: .value(T("余额", "Balance"), sample.value)
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
                    x: .value(T("时间", "Time"), sample.date),
                    y: .value(T("余额", "Balance"), sample.value)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            .chartXAxis(.hidden)

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

            axisLabels(samples)
        }
    }

    private func axisLabels(_ samples: [SamplePoint]) -> some View {
        let dates: [Date] = {
            guard let first = samples.first?.date, let last = samples.last?.date else { return [] }
            if samples.count < 3 { return [first, last] }
            return [first, samples[samples.count / 2].date, last]
        }()
        return HStack {
            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                Text(TideFormatter.axisDate(date))
                if index < dates.count - 1 {
                    Spacer()
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.top, 2)
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
