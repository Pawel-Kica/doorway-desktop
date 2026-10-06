import XCTest
@testable import DoorwayDesktopCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// UTC date in September 2026.
private func at(day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

private func entry(_ kind: LogKind, day: Int, _ hour: Int, app: String = "Signal", minutes: Int? = nil) -> LogEntry {
    LogEntry(ts: at(day: day, hour), bundleId: "id." + app, app: app, kind: kind, minutes: minutes)
}

/// "Now" in these tests: Wednesday 23 September 2026, 15:00 UTC.
private let now = at(day: 23, 15)

final class HistoryStatsTests: XCTestCase {
    func testOutcomeOfEveryKind() {
        XCTAssertEqual([LogKind.launch, .switch, .expired].map(\.outcome), [.opened, .opened, .opened])
        XCTAssertEqual(LogKind.cancelled.outcome, .notOpened)
        XCTAssertEqual(LogKind.later.outcome, .notOpened)
        XCTAssertEqual([LogKind.locked, .hidden].map(\.outcome), [.blocked, .blocked])
        XCTAssertNil(LogKind.quit.outcome)
        XCTAssertNil(LogKind.focus.outcome)
    }

    func testDaysAreOldestFirstWithEmptyDaysAndFocus() {
        let entries = [
            entry(.launch, day: 20, 9), entry(.cancelled, day: 20, 10), entry(.hidden, day: 22, 9),
            entry(.focus, day: 22, 11, minutes: 50), entry(.focus, day: 22, 16, minutes: 25), entry(.quit, day: 22, 17),
            entry(.locked, day: 23, 8), entry(.switch, day: 23, 14),
            entry(.launch, day: 10, 9), // Outside the window.
        ]
        let days = HistoryStats.days(entries, count: 4, now: now, calendar: utc)
        XCTAssertEqual(days.map(\.day), [at(day: 20, 0), at(day: 21, 0), at(day: 22, 0), at(day: 23, 0)])
        XCTAssertEqual(days.map(\.counts), [
            OutcomeCounts(opened: 1, notOpened: 1), OutcomeCounts(), OutcomeCounts(blocked: 1), OutcomeCounts(opened: 1, blocked: 1),
        ])
        XCTAssertEqual(days.map(\.focusMinutes), [0, 0, 75, 0])
    }

    func testTodayComparesWithTheWeekBefore() {
        // Before today: 16th to 22nd. Two opened + one didn't open on the 16th, one didn't open on the 22nd. 30 min focus on the 18th.
        var entries = [
            entry(.launch, day: 16, 9), entry(.launch, day: 16, 10), entry(.cancelled, day: 16, 11),
            entry(.cancelled, day: 22, 9), entry(.focus, day: 18, 12, minutes: 30),
            // Earlier, on the 12th and 15th: three opened, one blocked.
            entry(.launch, day: 12, 9), entry(.launch, day: 12, 10), entry(.expired, day: 15, 9), entry(.locked, day: 15, 10),
        ]
        entries += [entry(.launch, day: 23, 9), entry(.cancelled, day: 23, 10), entry(.cancelled, day: 23, 11)]
        let stats = HistoryStats.today(entries, now: now, calendar: utc)
        XCTAssertEqual(stats.attempts, 3)
        XCTAssertEqual(stats.attemptsAverage!, 4.0 / 7, accuracy: 0.0001)
        XCTAssertEqual(stats.opened, 1)
        XCTAssertEqual(stats.openedAverage!, 2.0 / 7, accuracy: 0.0001)
        // Last 7 days (17th to 23rd): 1 opened, 3 didn't open. The 7 before (10th to 16th): 5 opened, 1 didn't open, 1 blocked.
        XCTAssertEqual(stats.resisted!, 0.75, accuracy: 0.0001)
        XCTAssertEqual(stats.resistedBefore!, 2.0 / 7, accuracy: 0.0001)
        XCTAssertEqual(stats.focusMinutes, 0)
        XCTAssertEqual(stats.focusAverage!, 30.0 / 7, accuracy: 0.0001)
    }

    func testAveragesSkipDaysBeforeTheLogStarted() {
        let entries = [entry(.launch, day: 21, 9), entry(.launch, day: 21, 10), entry(.launch, day: 22, 9), entry(.launch, day: 23, 9)]
        let stats = HistoryStats.today(entries, now: now, calendar: utc)
        XCTAssertEqual(stats.openedAverage!, 1.5, accuracy: 0.0001)
        XCTAssertEqual(stats.resisted!, 0, accuracy: 0.0001)
        XCTAssertNil(stats.resistedBefore)
    }

    func testFirstDayHasNoBaseline() {
        let stats = HistoryStats.today([entry(.launch, day: 23, 9)], now: now, calendar: utc)
        XCTAssertNil(stats.attemptsAverage)
        XCTAssertNil(stats.openedAverage)
        XCTAssertNil(stats.focusAverage)
        XCTAssertNil(HistoryStats.today([], now: now, calendar: utc).resisted)
    }

    func testTopAppsByAttemptsThenName() {
        let entries = [
            entry(.launch, day: 23, 9, app: "WhatsApp"), entry(.cancelled, day: 22, 9, app: "WhatsApp"),
            entry(.cancelled, day: 23, 9), entry(.locked, day: 22, 9), entry(.launch, day: 21, 9),
            entry(.launch, day: 23, 9, app: "Messages"), entry(.launch, day: 23, 10, app: "Mail"),
            entry(.quit, day: 23, 11, app: "Doorway Desktop"), entry(.focus, day: 23, 12, app: "Focus", minutes: 30),
            entry(.launch, day: 1, 9, app: "Old"), // Outside a 20-day window, which starts on the 4th.
        ]
        let apps = HistoryStats.topApps(entries, days: 20, limit: 4, now: now, calendar: utc)
        XCTAssertEqual(apps.map(\.app), ["Signal", "WhatsApp", "Mail", "Messages"])
        XCTAssertEqual(apps[0].counts, OutcomeCounts(opened: 1, notOpened: 1, blocked: 1))
        XCTAssertEqual(HistoryStats.topApps(entries, days: 20, now: now, calendar: utc).count, 4)
        XCTAssertEqual(HistoryStats.topApps(entries, days: 30, now: now, calendar: utc).last?.app, "Old")
        XCTAssertEqual(HistoryStats.topApps(entries, days: 1, now: now, calendar: utc).map(\.app), ["Mail", "Messages", "Signal", "WhatsApp"])
    }

    func testTopAppsUsesNewestName() {
        let entries = [entry(.launch, day: 22, 9), LogEntry(ts: at(day: 23, 9), bundleId: "id.Signal", app: "Signal Beta", kind: .launch)]
        XCTAssertEqual(HistoryStats.topApps(entries, now: now, calendar: utc).map(\.app), ["Signal Beta"])
    }

    func testByHourOverWindow() {
        let entries = [
            entry(.launch, day: 23, 9), entry(.cancelled, day: 20, 9), entry(.hidden, day: 23, 0),
            entry(.focus, day: 23, 9, minutes: 30), entry(.launch, day: 1, 9),
        ]
        let hours = HistoryStats.byHour(entries, days: 7, now: now, calendar: utc)
        XCTAssertEqual(hours.count, 24)
        XCTAssertEqual(hours[9], OutcomeCounts(opened: 1, notOpened: 1))
        XCTAssertEqual(hours[0], OutcomeCounts(blocked: 1))
        XCTAssertEqual(hours.map(\.total).reduce(0, +), 3)
    }
}
