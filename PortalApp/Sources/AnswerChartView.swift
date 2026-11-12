import Charts
import PortalKit
import SwiftUI

/// AnswerChartView draws a chart the assistant wrote in an answer: bars, lines with their points, or a pie with its slices
/// named, under the chart's title. A series is told apart by color, with a legend when there is more than one.
struct AnswerChartView: View {
    let chart: AnswerChart
    @ScaledMetric(relativeTo: .body) private var plotHeight: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title = chart.title {
                Text(title).font(.subheadline.weight(.semibold))
            }
            plot
                .frame(height: plotHeight)
        }
        .padding(12)
        .background(Color.portalCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilitySummary))
        .accessibilityIdentifier("answerChart")
    }

    private var isLegendShown: Bool { chart.kind == .pie || chart.series.count > 1 }

    @ViewBuilder
    private var plot: some View {
        switch chart.kind {
        case .bar:
            Chart(chart.points) { point in
                BarMark(x: .value(chart.xAxisLabel ?? "Category", point.category), y: .value(chart.yAxisLabel ?? "Value", point.value))
                    .foregroundStyle(by: .value("Series", point.seriesName))
                    .position(by: .value("Series", point.seriesName))
            }
            .chartLegend(isLegendShown ? .visible : .hidden)
        case .line:
            Chart(chart.points) { point in
                LineMark(x: .value(chart.xAxisLabel ?? "Category", point.category), y: .value(chart.yAxisLabel ?? "Value", point.value))
                    .foregroundStyle(by: .value("Series", point.seriesName))
                PointMark(x: .value(chart.xAxisLabel ?? "Category", point.category), y: .value(chart.yAxisLabel ?? "Value", point.value))
                    .foregroundStyle(by: .value("Series", point.seriesName))
            }
            .chartLegend(isLegendShown ? .visible : .hidden)
        case .pie:
            Chart(chart.points) { point in
                SectorMark(angle: .value("Value", point.value), innerRadius: .ratio(0.5), angularInset: 1)
                    .foregroundStyle(by: .value("Slice", point.category))
            }
            .chartLegend(position: .trailing, alignment: .center)
        }
    }

    /// What VoiceOver reads: the title, then each series with its values.
    private var accessibilitySummary: String {
        let values = chart.series.map { series in
            let names = chart.kind == .pie ? series.labels : chart.categories
            let pairs = series.values.enumerated().map { index, value in
                let name = index < names.count ? names[index] : "\(index + 1)"
                return "\(name) \(value.formatted())"
            }
            return "\(series.name): \(pairs.joined(separator: ", "))"
        }
        return ([chart.title].compactMap { $0 } + values).joined(separator: ". ")
    }
}
