import Charts
import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case month = "1M", quarter = "3M", half = "6M", year = "1Y", all = "All"
    var id: String { rawValue }

    var startDate: Date? {
        let cal = Calendar.current
        switch self {
        case .month: return cal.date(byAdding: .month, value: -1, to: .now)
        case .quarter: return cal.date(byAdding: .month, value: -3, to: .now)
        case .half: return cal.date(byAdding: .month, value: -6, to: .now)
        case .year: return cal.date(byAdding: .year, value: -1, to: .now)
        case .all: return nil
        }
    }
}

struct TrendPoint: Identifiable, Hashable {
    let id: UUID
    let date: Date
    let value: Double
    var label: String? = nil
}

/// Line + area chart with drag-to-inspect, used for strength and body-weight trends.
struct TrendChart: View {
    let points: [TrendPoint]
    var smoothed: [TrendPoint] = []
    var goal: Double? = nil
    var tint: Color = Theme.ember
    var unit: String = "lb"
    var height: CGFloat = 220
    var showsPoints = true
    var valueFormatter: (Double) -> String = { Fmt.weight($0) }

    @State private var selectedDate: Date?

    private var selected: TrendPoint? {
        guard let selectedDate else { return nil }
        let source = smoothed.isEmpty ? points : points
        return source.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value) + smoothed.map(\.value) + (goal.map { [$0] } ?? [])
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, hi * 0.01, 1)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            let lineSource = smoothed.isEmpty ? points : smoothed
            ForEach(lineSource) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", yDomain.lowerBound), yEnd: .value("Value", p.value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.monotone)
            }
            if showsPoints {
                ForEach(points) { p in
                    PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .foregroundStyle(smoothed.isEmpty ? tint : tint.opacity(0.35))
                        .symbolSize(smoothed.isEmpty ? 28 : 16)
                }
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(Theme.success.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal \(valueFormatter(goal))")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.success)
                    }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 2) {
                            Text("\(valueFormatter(selected.value)) \(unit)")
                                .font(.subheadline.weight(.bold))
                                .monospacedDigit()
                            Text(selected.label ?? selected.date.formatted(.dateTime.month(.abbreviated).day()))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                    .foregroundStyle(tint)
                    .symbolSize(90)
            }
        }
        .chartYScale(domain: yDomain)
        .chartXScale(range: .plotDimension(startPadding: 6, endPadding: 22))
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(valueFormatter(v)) }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: xAxisDates) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
            }
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: selected?.id)
    }

    /// Four evenly spaced dates kept away from the plot edges so no label gets clipped.
    private var xAxisDates: [Date] {
        let dates = points.map(\.date) + smoothed.map(\.date)
        guard let lo = dates.min(), let hi = dates.max(), hi > lo else { return dates }
        let span = hi.timeIntervalSince(lo)
        return [0.1, 0.36, 0.62, 0.88].map { lo.addingTimeInterval(span * $0) }
    }
}

struct RangePicker: View {
    @Binding var range: ChartRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
