import Foundation

/// The time span a statistics screen covers.
enum StatsPeriod: String, CaseIterable, Identifiable, Hashable {
    case day, week, month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        }
    }

    /// The calendar component used to step between periods.
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// Focus totals for one calendar day.
struct DayBucket: Identifiable, Hashable {
    /// Start of the day.
    let date: Date
    var focusedSeconds: Int = 0
    var completedCount: Int = 0
    var stoppedCount: Int = 0

    var id: Date { date }
    var sessionCount: Int { completedCount + stoppedCount }
}

/// Focus totals for one hour of a day.
struct HourBucket: Identifiable, Hashable {
    /// 0...23
    let hour: Int
    /// Start of the hour.
    let date: Date
    var focusedSeconds: Int = 0
    var sessionCount: Int = 0

    var id: Int { hour }
}

struct StatsSummary: Hashable {
    var focusedSeconds: Int
    var completedCount: Int
    var stoppedCount: Int
    /// Focused seconds divided by the days of the interval that have started (up to today).
    var dailyAverageSeconds: Int
    /// The day with the most focus time; nil when nothing was recorded.
    var bestDay: DayBucket?

    var sessionCount: Int { completedCount + stoppedCount }
}

/// Pure statistics over `SessionRecord`s. Sessions are attributed to the day/hour of their start date.
enum Stats {
    /// The day, week (respecting `calendar.firstWeekday`) or month containing `date`.
    static func interval(for period: StatsPeriod, containing date: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: period.component, for: date) {
            return interval
        }
        // Not expected for the Gregorian calendar; fall back to the containing day.
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    /// Start of every day in `interval`.
    static func days(in interval: DateInterval, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = calendar.startOfDay(for: interval.start)
        while day < interval.end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return days
    }

    /// One bucket per day of `interval`, zero-filled.
    static func dailyBuckets(records: [SessionRecord], in interval: DateInterval, calendar: Calendar) -> [DayBucket] {
        var buckets = days(in: interval, calendar: calendar).map { DayBucket(date: $0) }
        var index: [Date: Int] = [:]
        for (i, bucket) in buckets.enumerated() { index[bucket.date] = i }

        for record in records where contains(interval, record.startDate) {
            guard let i = index[calendar.startOfDay(for: record.startDate)] else { continue }
            buckets[i].focusedSeconds += max(0, record.focusedSeconds)
            if record.completed {
                buckets[i].completedCount += 1
            } else {
                buckets[i].stoppedCount += 1
            }
        }
        return buckets
    }

    /// 24 hourly buckets for the day containing `day`, zero-filled.
    static func hourlyBuckets(records: [SessionRecord], day: Date, calendar: Calendar) -> [HourBucket] {
        let dayStart = calendar.startOfDay(for: day)
        var buckets = (0..<24).map { hour in
            HourBucket(hour: hour, date: calendar.date(byAdding: .hour, value: hour, to: dayStart) ?? dayStart)
        }
        for record in records where calendar.isDate(record.startDate, inSameDayAs: dayStart) {
            let hour = calendar.component(.hour, from: record.startDate)
            guard buckets.indices.contains(hour) else { continue }
            buckets[hour].focusedSeconds += max(0, record.focusedSeconds)
            buckets[hour].sessionCount += 1
        }
        return buckets
    }

    static func summary(records: [SessionRecord], in interval: DateInterval, calendar: Calendar, now: Date = .now) -> StatsSummary {
        let buckets = dailyBuckets(records: records, in: interval, calendar: calendar)
        let focused = buckets.reduce(0) { $0 + $1.focusedSeconds }
        let completed = buckets.reduce(0) { $0 + $1.completedCount }
        let stopped = buckets.reduce(0) { $0 + $1.stoppedCount }

        // Only days that have already begun count towards the average.
        let elapsedDays = buckets.filter { $0.date <= now }.count
        let average = elapsedDays > 0 ? focused / elapsedDays : 0

        var best: DayBucket?
        for bucket in buckets where bucket.focusedSeconds > 0 {
            if bucket.focusedSeconds > (best?.focusedSeconds ?? 0) { best = bucket }
        }

        return StatsSummary(
            focusedSeconds: focused,
            completedCount: completed,
            stoppedCount: stopped,
            dailyAverageSeconds: average,
            bestDay: best
        )
    }

    /// Consecutive days with at least one completed session, ending today
    /// (or ending yesterday when today has no completed session yet).
    static func currentStreak(records: [SessionRecord], today: Date, calendar: Calendar) -> Int {
        let completedDays = Set(records.filter(\.completed).map { calendar.startOfDay(for: $0.startDate) })
        var day = calendar.startOfDay(for: today)
        if !completedDays.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while completedDays.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// "0m", "45m", "1h 05m".
    static func formatDuration(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let hours = minutes / 60
        if hours == 0 { return String(localized: "\(minutes)m") }
        return String(localized: "\(hours)h \(String(format: "%02d", minutes % 60))m")
    }

    private static func contains(_ interval: DateInterval, _ date: Date) -> Bool {
        date >= interval.start && date < interval.end
    }
}
