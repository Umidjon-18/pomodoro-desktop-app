import XCTest
@testable import Pomodoro

final class StatsTests: XCTestCase {
    private func calendar(firstWeekday: Int = 2) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = firstWeekday
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func record(_ start: Date, minutes: Int = 25, focused: Int? = nil, completed: Bool = true) -> SessionRecord {
        SessionRecord(startDate: start, plannedMinutes: minutes, focusedSeconds: focused ?? minutes * 60, completed: completed)
    }

    // MARK: - Intervals

    func testDayInterval() {
        let interval = Stats.interval(for: .day, containing: date(2026, 10, 10, 15, 30), calendar: calendar())
        XCTAssertEqual(interval.start, date(2026, 10, 10))
        XCTAssertEqual(interval.end, date(2026, 10, 11))
    }

    func testWeekIntervalStartingSunday() {
        // Saturday 10 Oct 2026.
        let interval = Stats.interval(for: .week, containing: date(2026, 10, 10, 12), calendar: calendar(firstWeekday: 1))
        XCTAssertEqual(interval.start, date(2026, 10, 4))
        XCTAssertEqual(interval.end, date(2026, 10, 11))
    }

    func testWeekIntervalStartingMonday() {
        let interval = Stats.interval(for: .week, containing: date(2026, 10, 10, 12), calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(interval.start, date(2026, 10, 5))
        XCTAssertEqual(interval.end, date(2026, 10, 12))
    }

    func testWeekIntervalOnFirstWeekday() {
        // Sunday 4 Oct 2026: first day of a Sunday-week, last day of a Monday-week.
        let sunday = date(2026, 10, 4, 9)
        XCTAssertEqual(Stats.interval(for: .week, containing: sunday, calendar: calendar(firstWeekday: 1)).start, date(2026, 10, 4))
        XCTAssertEqual(Stats.interval(for: .week, containing: sunday, calendar: calendar(firstWeekday: 2)).start, date(2026, 9, 28))
    }

    func testWeekIntervalAcrossYearBoundary() {
        let interval = Stats.interval(for: .week, containing: date(2026, 1, 1), calendar: calendar(firstWeekday: 2))
        XCTAssertEqual(interval.start, date(2025, 12, 29))
        XCTAssertEqual(interval.end, date(2026, 1, 5))
        XCTAssertEqual(Stats.days(in: interval, calendar: calendar()).count, 7)
    }

    func testMonthIntervals() {
        let cal = calendar()
        let october = Stats.interval(for: .month, containing: date(2026, 10, 10), calendar: cal)
        XCTAssertEqual(october.start, date(2026, 10, 1))
        XCTAssertEqual(october.end, date(2026, 11, 1))
        XCTAssertEqual(Stats.days(in: october, calendar: cal).count, 31)

        let april = Stats.interval(for: .month, containing: date(2026, 4, 30, 23, 59), calendar: cal)
        XCTAssertEqual(Stats.days(in: april, calendar: cal).count, 30)

        let february = Stats.interval(for: .month, containing: date(2026, 2, 14), calendar: cal)
        XCTAssertEqual(Stats.days(in: february, calendar: cal).count, 28)

        let leapFebruary = Stats.interval(for: .month, containing: date(2028, 2, 14), calendar: cal)
        XCTAssertEqual(leapFebruary.start, date(2028, 2, 1))
        XCTAssertEqual(leapFebruary.end, date(2028, 3, 1))
        XCTAssertEqual(Stats.days(in: leapFebruary, calendar: cal).count, 29)
    }

    // MARK: - Buckets

    func testDailyBucketsAreZeroFilled() {
        let cal = calendar()
        let week = Stats.interval(for: .week, containing: date(2026, 10, 7), calendar: cal)
        let buckets = Stats.dailyBuckets(records: [], in: week, calendar: cal)
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets.first?.date, date(2026, 10, 5))
        XCTAssertEqual(buckets.last?.date, date(2026, 10, 11))
        XCTAssertTrue(buckets.allSatisfy { $0.focusedSeconds == 0 && $0.completedCount == 0 && $0.stoppedCount == 0 })
    }

    func testDailyBucketsAggregateByStartDay() {
        let cal = calendar()
        let week = Stats.interval(for: .week, containing: date(2026, 10, 7), calendar: cal)
        let records = [
            record(date(2026, 10, 5, 9)),                                         // Mon, 25m completed
            record(date(2026, 10, 5, 14), minutes: 45, focused: 600, completed: false), // Mon, 10m stopped
            record(date(2026, 10, 7, 23, 50), minutes: 25),                       // Wed, crosses midnight
            record(date(2026, 10, 4, 22)),                                        // previous week
            record(date(2026, 10, 12, 0, 0)),                                     // next week
        ]
        let buckets = Stats.dailyBuckets(records: records, in: week, calendar: cal)
        XCTAssertEqual(buckets.count, 7)
        XCTAssertEqual(buckets[0].focusedSeconds, 1500 + 600)
        XCTAssertEqual(buckets[0].completedCount, 1)
        XCTAssertEqual(buckets[0].stoppedCount, 1)
        XCTAssertEqual(buckets[1].focusedSeconds, 0)
        XCTAssertEqual(buckets[2].focusedSeconds, 1500)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.sessionCount }, 3)
    }

    func testHourlyBuckets() {
        let cal = calendar()
        let records = [
            record(date(2026, 10, 10, 9, 5)),
            record(date(2026, 10, 10, 9, 40), focused: 300, completed: false),
            record(date(2026, 10, 10, 23, 59)),
            record(date(2026, 10, 11, 0, 1)),
        ]
        let buckets = Stats.hourlyBuckets(records: records, day: date(2026, 10, 10, 12), calendar: cal)
        XCTAssertEqual(buckets.count, 24)
        XCTAssertEqual(buckets[0].date, date(2026, 10, 10))
        XCTAssertEqual(buckets[9].date, date(2026, 10, 10, 9))
        XCTAssertEqual(buckets[9].focusedSeconds, 1800)
        XCTAssertEqual(buckets[9].sessionCount, 2)
        XCTAssertEqual(buckets[23].sessionCount, 1)
        XCTAssertEqual(buckets[0].sessionCount, 0)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.sessionCount }, 3)
    }

    // MARK: - Summary

    func testSummaryCountsAndAverage() {
        let cal = calendar()
        let week = Stats.interval(for: .week, containing: date(2026, 10, 7), calendar: cal)
        let records = [
            record(date(2026, 10, 5, 9), minutes: 60),
            record(date(2026, 10, 6, 9), minutes: 25),
            record(date(2026, 10, 6, 11), minutes: 45, focused: 900, completed: false),
            record(date(2026, 10, 1, 9), minutes: 60), // outside
        ]
        // "Now" is Wednesday afternoon: three days (Mon, Tue, Wed) have started.
        let summary = Stats.summary(records: records, in: week, calendar: cal, now: date(2026, 10, 7, 15))
        XCTAssertEqual(summary.focusedSeconds, 3600 + 1500 + 900)
        XCTAssertEqual(summary.completedCount, 2)
        XCTAssertEqual(summary.stoppedCount, 1)
        XCTAssertEqual(summary.sessionCount, 3)
        XCTAssertEqual(summary.dailyAverageSeconds, (3600 + 1500 + 900) / 3)
        XCTAssertEqual(summary.bestDay?.date, date(2026, 10, 5))
        XCTAssertEqual(summary.bestDay?.focusedSeconds, 3600)
    }

    func testSummaryOfPastPeriodAveragesOverAllDays() {
        let cal = calendar()
        let week = Stats.interval(for: .week, containing: date(2026, 9, 30), calendar: cal)
        let summary = Stats.summary(records: [record(date(2026, 9, 29, 10), minutes: 70)], in: week, calendar: cal, now: date(2026, 10, 10))
        XCTAssertEqual(summary.dailyAverageSeconds, 600)
    }

    func testEmptySummary() {
        let cal = calendar()
        let month = Stats.interval(for: .month, containing: date(2026, 10, 10), calendar: cal)
        let summary = Stats.summary(records: [], in: month, calendar: cal, now: date(2026, 10, 10))
        XCTAssertEqual(summary.focusedSeconds, 0)
        XCTAssertEqual(summary.dailyAverageSeconds, 0)
        XCTAssertNil(summary.bestDay)
    }

    // MARK: - Streak

    func testStreakCountsToday() {
        let records = [
            record(date(2026, 10, 10, 8)),
            record(date(2026, 10, 9, 8)),
            record(date(2026, 10, 8, 20)),
        ]
        XCTAssertEqual(Stats.currentStreak(records: records, today: date(2026, 10, 10, 18), calendar: calendar()), 3)
    }

    func testStreakEndsYesterdayWhenTodayHasNothingYet() {
        let records = [
            record(date(2026, 10, 9, 8)),
            record(date(2026, 10, 8, 20)),
        ]
        XCTAssertEqual(Stats.currentStreak(records: records, today: date(2026, 10, 10, 7), calendar: calendar()), 2)
    }

    func testStreakIgnoresStoppedSessionsAndBreaksOnGap() {
        let records = [
            record(date(2026, 10, 10, 8)),
            record(date(2026, 10, 9, 8), focused: 600, completed: false), // stopped: does not count
            record(date(2026, 10, 8, 8)),
            record(date(2026, 10, 7, 8)),
        ]
        XCTAssertEqual(Stats.currentStreak(records: records, today: date(2026, 10, 10, 18), calendar: calendar()), 1)
    }

    func testStreakIsZeroWhenLastCompletionIsOlderThanYesterday() {
        let records = [record(date(2026, 10, 8, 8))]
        XCTAssertEqual(Stats.currentStreak(records: records, today: date(2026, 10, 10, 18), calendar: calendar()), 0)
        XCTAssertEqual(Stats.currentStreak(records: [], today: date(2026, 10, 10), calendar: calendar()), 0)
    }

    // MARK: - Formatting

    func testFormatDuration() {
        XCTAssertEqual(Stats.formatDuration(seconds: 0), "0m")
        XCTAssertEqual(Stats.formatDuration(seconds: 59), "0m")
        XCTAssertEqual(Stats.formatDuration(seconds: 45 * 60), "45m")
        XCTAssertEqual(Stats.formatDuration(seconds: 60 * 60), "1h 00m")
        XCTAssertEqual(Stats.formatDuration(seconds: 65 * 60 + 30), "1h 05m")
        XCTAssertEqual(Stats.formatDuration(seconds: 10 * 3600 + 59 * 60), "10h 59m")
        XCTAssertEqual(Stats.formatDuration(seconds: -5), "0m")
    }
}
