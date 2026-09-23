import AppKit
import Charts
import SimpleBlockCore
import SwiftUI

/// KPI tiles and charts for the top of the History pane. `scale` multiplies every font size and fixed dimension.
struct HistoryDashboard: View {
    let entries: [LogEntry]
    let now: Date
    var scale: CGFloat = 1

    var body: some View {
        let calendar = Calendar.current
        let today = HistoryStats.today(entries, now: now, calendar: calendar)
        let days = HistoryStats.days(entries, count: 14, now: now, calendar: calendar)
        let hours = HistoryStats.byHour(entries, now: now, calendar: calendar)
        VStack(alignment: .leading, spacing: 12 * scale) {
            HStack(spacing: 12 * scale) {
                KPITile(title: "Attempts today", value: "\(today.attempts)",
                        note: average(today.attemptsAverage, number),
                        trend: trend(Double(today.attempts), today.attemptsAverage, higherIsBetter: false), scale: scale)
                KPITile(title: "Opened today", value: "\(today.opened)",
                        note: average(today.openedAverage, number),
                        trend: trend(Double(today.opened), today.openedAverage, higherIsBetter: false), scale: scale)
                KPITile(title: "Resisted, 7 days", value: today.resisted.map(percent) ?? "-",
                        note: today.resistedBefore.map { "Week before \(percent($0))" } ?? "Nothing to compare yet",
                        trend: today.resisted.flatMap { trend($0 * 100, today.resistedBefore.map { $0 * 100 }, higherIsBetter: true) },
                        scale: scale)
                // Only once focus sessions exist, so it doesn't sit at zero forever.
                if entries.contains(where: { $0.kind == .focus }) {
                    KPITile(title: "Focus today", value: duration(Double(today.focusMinutes)),
                            note: average(today.focusAverage, duration),
                            trend: trend(Double(today.focusMinutes), today.focusAverage, higherIsBetter: true), scale: scale)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Legend(scale: scale)
            StackedColumns(
                title: "Last 14 days",
                summary: describe(days.map(\.counts).reduce(OutcomeCounts(), +)),
                columns: days.map { day in
                    Column(id: "\(day.day.timeIntervalSince1970)",
                           axisLabel: day.day.formatted(.dateTime.weekday(.abbreviated)),
                           name: day.day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                           counts: day.counts)
                },
                plotHeight: 170, scale: scale)
            HStack(alignment: .top, spacing: 12 * scale) {
                TopApps(apps: HistoryStats.topApps(entries, now: now, calendar: calendar), scale: scale)
                StackedColumns(
                    title: "By hour",
                    summary: peak(hours).map { "Last 30 days, most at \(hourName($0))" } ?? "Last 30 days",
                    columns: hours.enumerated().map { hour, counts in
                        Column(id: "\(hour)", axisLabel: hour > 0 && hour % 6 == 0 ? hourName(hour) : nil, name: hourName(hour), counts: counts)
                    },
                    plotHeight: 130, scale: scale)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "7-day avg 4.3", or a placeholder on the first day.
    private func average(_ value: Double?, _ format: (Double) -> String) -> String {
        value.map { "7-day avg \(format($0))" } ?? "Nothing to compare yet"
    }

    /// Arrow and color for a value against its baseline, nil when they're about equal or there's no baseline.
    private func trend(_ value: Double, _ baseline: Double?, higherIsBetter: Bool) -> Trend? {
        guard let baseline, abs(value - baseline) >= 0.05 else { return nil }
        return Trend(up: value > baseline, good: (value > baseline) == higherIsBetter)
    }

    /// The busiest hour, nil without attempts.
    private func peak(_ hours: [OutcomeCounts]) -> Int? {
        guard let most = hours.map(\.total).max(), most > 0 else { return nil }
        return hours.firstIndex { $0.total == most }
    }

    /// "14:00" or "2 PM" style, following the user's locale.
    private func hourName(_ hour: Int) -> String {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now)!.formatted(date: .omitted, time: .shortened)
    }
}

extension Outcome {
    var label: String {
        switch self {
        case .opened: "Opened"
        case .neverMind: "Never mind"
        case .blocked: "Blocked"
        }
    }

    /// Checked as a set for colorblind separation in light and dark. Opened is the system blue of the launch pill.
    func color(_ scheme: ColorScheme) -> Color {
        switch self {
        case .opened: .blue
        case .neverMind: scheme == .dark ? Color(hex: 0x199E70) : Color(hex: 0x1BAF7A)
        case .blocked: scheme == .dark ? Color(hex: 0xD95926) : Color(hex: 0xEB6834)
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// "3 opened, 5 never mind", zero outcomes left out.
private func describe(_ counts: OutcomeCounts) -> String {
    let parts = Outcome.allCases.filter { counts[$0] > 0 }.map { "\(counts[$0]) \($0.label.lowercased())" }
    return parts.isEmpty ? "No attempts" : parts.joined(separator: ", ")
}

/// 4.3, or 4 when it's whole.
private func number(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...1)))
}

private func percent(_ share: Double) -> String {
    "\(Int((share * 100).rounded()))%"
}

/// "45m", "1h 20m", "2h".
private func duration(_ minutes: Double) -> String {
    let m = Int(minutes.rounded())
    if m < 60 { return "\(m)m" }
    return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
}

/// Direction of a KPI against its baseline and whether that's good news.
private struct Trend {
    let up: Bool
    let good: Bool
}

/// Rounded card like the History day cards. Not `Card`, which is the settings panes' row card.
private struct Tile<Content: View>: View {
    let scale: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16 * scale)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12 * scale))
            .overlay(RoundedRectangle(cornerRadius: 12 * scale).stroke(Color.primary.opacity(0.08)))
    }
}

/// Card with a title, a secondary line under it and a chart.
private struct ChartCard<Content: View>: View {
    let title: String
    let subtitle: String
    let scale: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        Tile(scale: scale) {
            VStack(alignment: .leading, spacing: 4 * scale) {
                Text(title).font(.system(size: 20 * scale, weight: .semibold))
                Text(subtitle).font(.system(size: 13 * scale)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                content.padding(.top, 14 * scale)
            }
        }
    }
}

/// One headline number with what it's compared to.
private struct KPITile: View {
    let title: String
    let value: String
    let note: String
    let trend: Trend?
    let scale: CGFloat

    var body: some View {
        Tile(scale: scale) {
            VStack(alignment: .leading, spacing: 6 * scale) {
                Text(title).font(.system(size: 15 * scale)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 34 * scale, weight: .semibold))
                HStack(spacing: 4 * scale) {
                    if let trend {
                        Image(systemName: trend.up ? "arrow.up.right" : "arrow.down.right")
                            .fontWeight(.bold)
                            .foregroundStyle(trend.good ? Color.green : Color.red)
                            .accessibilityLabel(trend.good ? "Better" : "Worse")
                    }
                    Text(note).foregroundStyle(.secondary).lineLimit(1)
                }
                .font(.system(size: 13 * scale))
            }
        }
    }
}

/// What the three colors mean, shared by every chart below it.
private struct Legend: View {
    let scale: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 18 * scale) {
            ForEach(Outcome.allCases, id: \.self) { outcome in
                HStack(spacing: 6 * scale) {
                    RoundedRectangle(cornerRadius: 3 * scale).fill(outcome.color(scheme))
                        .frame(width: 12 * scale, height: 12 * scale)
                    Text(outcome.label)
                }
            }
        }
        .font(.system(size: 13 * scale))
        .foregroundStyle(.secondary)
        .padding(.leading, 4 * scale)
    }
}

/// One column of a stacked chart.
private struct Column: Identifiable {
    let id: String
    /// Under the column, nil leaves it unlabeled.
    let axisLabel: String?
    /// Names the column in the hover readout.
    let name: String
    let counts: OutcomeCounts
}

/// Card with outcomes stacked per column, opened at the bottom. Hovering a column shows its numbers in the subtitle.
private struct StackedColumns: View {
    let title: String
    /// Subtitle while nothing is hovered.
    let summary: String
    let columns: [Column]
    /// Height of the plot area before scaling, fixed so the gap between segments can be exactly 2 pt.
    let plotHeight: CGFloat
    let scale: CGFloat
    @State private var hovered: String?
    @Environment(\.colorScheme) private var scheme

    /// One colored piece of a column.
    private struct Segment {
        let outcome: Outcome
        let start: Double
        let end: Double
        let isTop: Bool
    }

    var body: some View {
        let (top, step) = yAxis(columns.map(\.counts.total).max() ?? 0)
        let height = plotHeight * scale
        let gap = Double(top) * 2 * scale / height
        let hoveredColumn = columns.first { $0.id == hovered }
        let labels = Dictionary(uniqueKeysWithValues: columns.compactMap { column in column.axisLabel.map { (column.id, $0) } })
        ChartCard(title: title, subtitle: hoveredColumn.map { "\($0.name): \(describe($0.counts))" } ?? summary, scale: scale) {
            Chart {
                ForEach(columns) { column in
                    ForEach(segments(column.counts, gap: gap), id: \.outcome) { segment in
                        BarMark(x: .value("Column", column.id),
                                yStart: .value("From", segment.start), yEnd: .value("To", segment.end),
                                width: .ratio(0.6))
                            .foregroundStyle(segment.outcome.color(scheme))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: segment.isTop ? 4 * scale : 0,
                                                              topTrailingRadius: segment.isTop ? 4 * scale : 0))
                            .opacity(hovered == nil || hovered == column.id ? 1 : 0.35)
                    }
                }
            }
            .chartXScale(domain: columns.map(\.id)) // Keeps empty columns.
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: columns.map(\.id)) { value in
                    if let label = value.as(String.self).flatMap({ labels[$0] }) {
                        AxisValueLabel { Text(label).font(.system(size: 13 * scale)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: Array(stride(from: 0, through: top, by: step))) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Color.primary.opacity(0.1))
                    AxisValueLabel().font(.system(size: 13 * scale))
                }
            }
            .chartPlotStyle { $0.frame(height: height) }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case .active(let point) = phase, let plot = proxy.plotFrame else { return hovered = nil }
                            hovered = proxy.value(atX: point.x - geometry[plot].minX, as: String.self)
                        }
                }
            }
        }
    }

    /// Pieces of one column, bottom first, with `gap` taken out between neighbors so the total height stays true.
    private func segments(_ counts: OutcomeCounts, gap: Double) -> [Segment] {
        let parts = Outcome.allCases.filter { counts[$0] > 0 }
        var start = 0
        return parts.enumerated().map { index, outcome in
            let end = start + counts[outcome]
            defer { start = end }
            return Segment(outcome: outcome,
                           start: Double(start) + (index > 0 ? gap / 2 : 0),
                           end: Double(end) - (index < parts.count - 1 ? gap / 2 : 0),
                           isTop: index == parts.count - 1)
        }
    }

    /// Round axis top and tick step for the tallest column, at most 4 steps.
    private func yAxis(_ most: Int) -> (top: Int, step: Int) {
        let step = [1, 2, 5, 10, 20, 25, 50, 100, 250, 500].first { $0 * 4 >= most } ?? 1000
        return (max(step, (most + step - 1) / step * step), step)
    }
}

/// Card with the apps reached for most in the last 30 days, a stacked bar each with its total at the tip.
private struct TopApps: View {
    let apps: [AppStats]
    let scale: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let most = apps.map(\.counts.total).max() ?? 1
        ChartCard(title: "Top apps", subtitle: "Last 30 days", scale: scale) {
            if apps.isEmpty {
                Text("No attempts yet").font(.system(size: 15 * scale)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12 * scale) {
                ForEach(apps, id: \.bundleId) { app in
                    HStack(spacing: 10 * scale) {
                        icon(app.bundleId)
                        // Wide enough for "Google Chrome" and "Visual Studio Code"; 96 cut them short.
                        Text(app.app).font(.system(size: 15 * scale)).lineLimit(1)
                            .frame(width: 132 * scale, alignment: .leading)
                        GeometryReader { geometry in
                            let label = 34 * scale
                            HStack(spacing: 8 * scale) {
                                bar(app.counts, width: (geometry.size.width - label) * CGFloat(app.counts.total) / CGFloat(most))
                                Text("\(app.counts.total)").font(.system(size: 13 * scale)).monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 22 * scale)
                        .help(describe(app.counts))
                    }
                }
            }
        }
    }

    /// Outcomes side by side with a 2 pt gap, rounded at the tip, square at the baseline.
    private func bar(_ counts: OutcomeCounts, width: CGFloat) -> some View {
        let parts = Outcome.allCases.filter { counts[$0] > 0 }
        let gap = 2 * scale
        let room = max(0, width - gap * CGFloat(parts.count - 1))
        return HStack(spacing: gap) {
            ForEach(parts, id: \.self) { outcome in
                Rectangle().fill(outcome.color(scheme))
                    .frame(width: room * CGFloat(counts[outcome]) / CGFloat(counts.total))
            }
        }
        .frame(height: 14 * scale)
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 4 * scale, topTrailingRadius: 4 * scale))
    }

    /// The app's icon when it's installed, a placeholder otherwise.
    @ViewBuilder
    private func icon(_ bundleId: String) -> some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
                .frame(width: 22 * scale, height: 22 * scale)
        } else {
            Image(systemName: "app.dashed").font(.system(size: 16 * scale)).foregroundStyle(.secondary)
                .frame(width: 22 * scale, height: 22 * scale)
        }
    }
}
