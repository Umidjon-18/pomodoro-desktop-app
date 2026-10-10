import SwiftUI
import SwiftData
import Charts

/// Daily, weekly and monthly focus progress.
@MainActor
struct StatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FocusSession.startDate) private var sessions: [FocusSession]

    @State private var period: StatsPeriod = .week
    @State private var anchor: Date = .now
    @State private var selectedDate: Date?

    private var calendar: Calendar { .autoupdatingCurrent }
    private var interval: DateInterval { Stats.interval(for: period, containing: anchor, calendar: calendar) }
    private var isCurrentPeriod: Bool { interval.contains(.now) }

    var body: some View {
        let records = sessions.map(\.record)
        let summary = Stats.summary(records: records, in: interval, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                cards(summary: summary, records: records)
                chart(records: records, isEmpty: summary.sessionCount == 0)
                if period == .day {
                    sessionList
                }
            }
            .padding(20)
        }
        .navigationTitle("Progress")
        .onChange(of: period) { selectedDate = nil }
        .onChange(of: anchor) { selectedDate = nil }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(periodTitle)
                    .font(.title2.weight(.semibold))
                if let subtitle = periodSubtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()

            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            ControlGroup {
                Button {
                    step(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Previous")
                Button("Today") { anchor = .now }
                    .disabled(isCurrentPeriod)
                Button {
                    step(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Next")
                .disabled(isCurrentPeriod)
            }
            .fixedSize()
        }
    }

    private func step(_ value: Int) {
        if let date = calendar.date(byAdding: period.component, value: value, to: anchor) {
            anchor = min(date, .now)
        }
    }

    private var periodTitle: String {
        let start = interval.start
        let sameYear = calendar.isDate(start, equalTo: .now, toGranularity: .year)
        switch period {
        case .day:
            if calendar.isDateInToday(start) { return String(localized: "Today") }
            if calendar.isDateInYesterday(start) { return String(localized: "Yesterday") }
            let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day().month(.abbreviated)
            return start.formatted(sameYear ? style : style.year())
        case .week:
            if isCurrentPeriod { return String(localized: "This Week") }
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            return String(localized: "Week of \(start.formatted(sameYear ? style : style.year()))")
        case .month:
            return start.formatted(.dateTime.month(.wide).year())
        }
    }

    private var periodSubtitle: String? {
        switch period {
        case .day:
            guard calendar.isDateInToday(interval.start) || calendar.isDateInYesterday(interval.start) else { return nil }
            return interval.start.formatted(.dateTime.weekday(.wide).day().month(.wide))
        case .week:
            let last = interval.end.addingTimeInterval(-1)
            let style = Date.FormatStyle.dateTime.day().month(.abbreviated)
            return "\(interval.start.formatted(style)) – \(last.formatted(style))"
        case .month:
            return nil
        }
    }

    // MARK: Cards

    private func cards(summary: StatsSummary, records: [SessionRecord]) -> some View {
        let streak = Stats.currentStreak(records: records, today: .now, calendar: calendar)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            StatCard(title: "Focused time", value: Stats.formatDuration(seconds: summary.focusedSeconds),
                     symbol: "clock.fill", tint: .red)
            StatCard(title: "Completed sessions", value: "\(summary.completedCount)",
                     symbol: "checkmark.circle.fill", tint: .green)
            StatCard(title: "Stopped sessions", value: "\(summary.stoppedCount)",
                     symbol: "stop.circle.fill", tint: .orange)
            StatCard(title: "Day streak", value: "\(streak)",
                     symbol: "flame.fill", tint: .pink)
            if period != .day {
                StatCard(title: "Daily average", value: Stats.formatDuration(seconds: summary.dailyAverageSeconds),
                         symbol: "chart.line.flattrend.xyaxis", tint: .blue)
                StatCard(title: "Best day",
                         value: summary.bestDay.map { Stats.formatDuration(seconds: $0.focusedSeconds) } ?? "—",
                         symbol: "trophy.fill", tint: .yellow,
                         detail: summary.bestDay?.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            }
        }
    }

    // MARK: Chart

    private struct ChartPoint: Identifiable {
        let date: Date
        let seconds: Int
        let sessions: Int
        var id: Date { date }
        var minutes: Double { Double(seconds) / 60 }
    }

    private func chartPoints(records: [SessionRecord]) -> [ChartPoint] {
        switch period {
        case .day:
            return Stats.hourlyBuckets(records: records, day: interval.start, calendar: calendar)
                .map { ChartPoint(date: $0.date, seconds: $0.focusedSeconds, sessions: $0.sessionCount) }
        case .week, .month:
            return Stats.dailyBuckets(records: records, in: interval, calendar: calendar)
                .map { ChartPoint(date: $0.date, seconds: $0.focusedSeconds, sessions: $0.sessionCount) }
        }
    }

    private var chartUnit: Calendar.Component { period == .day ? .hour : .day }

    private func chart(records: [SessionRecord], isEmpty: Bool) -> some View {
        let points = chartPoints(records: records)
        let unit = chartUnit
        let selected = selectedDate.flatMap { date in
            points.first { calendar.isDate($0.date, equalTo: date, toGranularity: unit) }
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text(period == .day ? String(localized: "Focus by hour") : String(localized: "Focus by day"))
                .font(.headline)

            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Time", point.date, unit: unit),
                        y: .value("Minutes", point.minutes)
                    )
                    .foregroundStyle(Color.red.gradient)
                    .opacity(selected == nil || selected?.date == point.date ? 1 : 0.5)
                    .cornerRadius(3)
                }
                if let selected, selected.sessions > 0 {
                    RuleMark(x: .value("Selected", selected.date, unit: unit))
                        .foregroundStyle(Color.secondary.opacity(0.3))
                        .zIndex(-1)
                        .annotation(position: .top, spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTooltip(title: tooltipTitle(selected.date),
                                         value: Stats.formatDuration(seconds: selected.seconds),
                                         sessions: selected.sessions)
                        }
                }
            }
            .chartXScale(domain: interval.start...interval.end)
            .chartXSelection(value: $selectedDate)
            .chartXAxis { xAxis }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let minutes = value.as(Double.self) { Text(Self.axisLabel(minutes: minutes)) }
                    }
                }
            }
            .frame(height: 220)
            .overlay {
                if isEmpty {
                    Text("No focus sessions in this period")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    @AxisContentBuilder
    private var xAxis: some AxisContent {
        switch period {
        case .day:
            AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        case .week:
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 5)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.day(), centered: true)
            }
        }
    }

    private func tooltipTitle(_ date: Date) -> String {
        switch period {
        case .day:
            let end = calendar.date(byAdding: .hour, value: 1, to: date) ?? date
            return "\(date.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))"
        case .week, .month:
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
    }

    private static func axisLabel(minutes: Double) -> String {
        guard minutes >= 60 else { return String(localized: "\(Int(minutes))m") }
        let hours = minutes / 60
        let value = hours == hours.rounded() ? "\(Int(hours))" : hours.formatted(.number.precision(.fractionLength(1)))
        return String(localized: "\(value)h")
    }

    // MARK: Session list (day)

    private var daySessions: [FocusSession] {
        let range = interval
        return sessions.filter { $0.startDate >= range.start && $0.startDate < range.end }
    }

    private var sessionList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sessions")
                .font(.headline)

            let items = daySessions
            if items.isEmpty {
                Text("No sessions on this day.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 { Divider() }
                        SessionRow(session: item)
                            .contextMenu {
                                Button("Delete Session", role: .destructive) {
                                    modelContext.delete(item)
                                    try? modelContext.save()
                                }
                            }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            }
        }
    }
}

// MARK: - Components

private struct StatCard: View {
    let title: LocalizedStringKey
    let value: String
    let symbol: String
    let tint: Color
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.callout)
                .foregroundStyle(.secondary)
                .symbolRenderingMode(.monochrome)
                .labelStyle(TintedIconLabelStyle(tint: tint))
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title.weight(.semibold))
                    .monospacedDigit()
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }
}

private struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}

private struct ChartTooltip: View {
    let title: String
    let value: String
    let sessions: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            Text("Sessions: \(sessions)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SessionRow: View {
    let session: FocusSession

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.completed ? "checkmark.circle.fill" : "stop.circle.fill")
                .font(.title3)
                .foregroundStyle(session.completed ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(session.startDate.formatted(date: .omitted, time: .shortened)) – \(session.endDate.formatted(date: .omitted, time: .shortened))")
                    .monospacedDigit()
                Text("Planned \(session.plannedMinutes) min · focused \(Stats.formatDuration(seconds: session.focusedSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(session.completed ? String(localized: "Completed") : String(localized: "Stopped"))
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((session.completed ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                .foregroundStyle(session.completed ? Color.green : Color.orange)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
