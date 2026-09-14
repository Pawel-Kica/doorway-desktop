import XCTest
@testable import SimpleBlockCore

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// UTC date in September 2026. The 14th is a Monday (weekday 2).
private func date(day: Int = 14, _ hour: Int, _ minute: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
}

final class ScheduleTests: XCTestCase {
    func testDefaultIsEveryDayAllDay() {
        let schedule = Schedule()
        for day in 14...20 {
            for hour in [0, 9, 23] { XCTAssertTrue(schedule.isActive(at: date(day: day, hour), calendar: utc)) }
        }
    }

    func testDaytimeRangeIncludesStartExcludesEnd() {
        let schedule = Schedule(from: 9 * 60, to: 17 * 60)
        XCTAssertFalse(schedule.isActive(at: date(8, 59), calendar: utc))
        XCTAssertTrue(schedule.isActive(at: date(9, 0), calendar: utc))
        XCTAssertTrue(schedule.isActive(at: date(16, 59), calendar: utc))
        XCTAssertFalse(schedule.isActive(at: date(17, 0), calendar: utc))
    }

    func testDisabledDayIsOff() {
        let schedule = Schedule(days: [1, 3, 4, 5, 6, 7])
        XCTAssertFalse(schedule.isActive(at: date(12), calendar: utc))
        XCTAssertTrue(schedule.isActive(at: date(day: 15, 12), calendar: utc))
    }

    func testOvernightWrapsPastMidnight() {
        let schedule = Schedule(days: [2], from: 22 * 60, to: 7 * 60)
        XCTAssertTrue(schedule.isActive(at: date(23), calendar: utc))
        XCTAssertTrue(schedule.isActive(at: date(day: 15, 3), calendar: utc), "Tuesday 03:00 is Monday night's tail")
        XCTAssertFalse(schedule.isActive(at: date(day: 15, 7), calendar: utc))
        XCTAssertFalse(schedule.isActive(at: date(3), calendar: utc), "Sunday night is off")
        XCTAssertFalse(schedule.isActive(at: date(12), calendar: utc))
    }

    func testOvernightFromSaturdayIntoSunday() {
        let schedule = Schedule(days: [7], from: 22 * 60, to: 7 * 60)
        XCTAssertTrue(schedule.isActive(at: date(day: 20, 3), calendar: utc))
    }
}

final class TimerTests: XCTestCase {
    func testTimerRunsFixedLengthFromStart() {
        var timers = AppTimers()
        timers.start("signal", minutes: 5, now: date(12))
        XCTAssertEqual(timers.remaining("signal", now: date(12)), 300)
        XCTAssertEqual(timers.remaining("signal", now: date(12, 4)), 60)
        XCTAssertTrue(timers.isRunning("signal", now: date(12, 4)))
        XCTAssertFalse(timers.isRunning("signal", now: date(12, 5)))
    }

    func testTimersArePerApp() {
        var timers = AppTimers()
        timers.start("signal", minutes: 5, now: date(12))
        XCTAssertFalse(timers.isRunning("slack", now: date(12)))
    }

    func testPopExpiredRemovesOnlyEndedTimers() {
        var timers = AppTimers()
        timers.start("signal", minutes: 1, now: date(12))
        timers.start("slack", minutes: 5, now: date(12))
        XCTAssertEqual(timers.popExpired(now: date(12, 1)), ["signal"])
        XCTAssertNil(timers.ends["signal"])
        XCTAssertEqual(timers.popExpired(now: date(12, 1)), [])
        XCTAssertTrue(timers.isRunning("slack", now: date(12, 1)))
    }

    func testSoonestPicksFirstToEnd() {
        var timers = AppTimers()
        XCTAssertNil(timers.soonest(now: date(12)))
        timers.start("slack", minutes: 5, now: date(12))
        timers.start("signal", minutes: 2, now: date(12))
        XCTAssertEqual(timers.soonest(now: date(12))?.bundleId, "signal")
        XCTAssertEqual(timers.soonest(now: date(12, 3))?.bundleId, "slack")
    }

    func testCountdown() {
        XCTAssertEqual(countdown(192), "3:12")
        XCTAssertEqual(countdown(60), "1:00")
        XCTAssertEqual(countdown(0.4), "0:01")
    }
}

final class WordCountTests: XCTestCase {
    func testCountsWhitespaceSeparatedTokens() {
        XCTAssertEqual(wordCount(""), 0)
        XCTAssertEqual(wordCount("   \n "), 0)
        XCTAssertEqual(wordCount("  one  two\nthree\t four "), 4)
        XCTAssertEqual(wordCount("a b c d e f g h i j"), minimumWords)
    }
}

final class LogTests: XCTestCase {
    private let plusTwo = TimeZone(secondsFromGMT: 7200)!

    private func json(_ line: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    }

    func testEncodesReasonEntryWithLocalOffset() throws {
        let entry = LogEntry(ts: date(12, 5), bundleId: "org.whispersystems.signal-desktop", app: "Signal", kind: .launch, reason: "a/b reply")
        let line = try LogCodec.encode(entry, timeZone: plusTwo)
        let object = try json(line)
        XCTAssertFalse(line.contains("\n"))
        XCTAssertEqual(Set(object.keys), ["ts", "bundleId", "app", "kind", "reason"])
        XCTAssertEqual(object["ts"] as? String, "2026-09-14T14:05:00+02:00")
        XCTAssertEqual(object["kind"] as? String, "launch")
        XCTAssertEqual(object["reason"] as? String, "a/b reply")
    }

    func testCancelledHasNoReasonKey() throws {
        let entry = LogEntry(ts: date(12), bundleId: "x", app: "X", kind: .cancelled)
        XCTAssertEqual(Set(try json(LogCodec.encode(entry)).keys), ["ts", "bundleId", "app", "kind"])
    }

    func testRoundTrip() throws {
        let entry = LogEntry(ts: date(12), bundleId: "x", app: "X", kind: .switch, reason: "why")
        XCTAssertEqual(try LogCodec.decode(LogCodec.encode(entry, timeZone: plusTwo)), entry)
    }

    func testAppendsLinesAndSkipsBadOnes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let log = ReasonLog(url: dir.appendingPathComponent("reasons.jsonl"))
        XCTAssertEqual(log.readAll(), [])
        let first = LogEntry(ts: date(12), bundleId: "x", app: "X", kind: .launch, reason: "one")
        let second = LogEntry(ts: date(13), bundleId: "x", app: "X", kind: .quit)
        try log.append(first)
        try Data("not json\n".utf8).append(to: log.url)
        try log.append(second)
        XCTAssertEqual(log.readAll(), [first, second])
    }

    func testReasonsTodayCountsOnlyReasonKinds() {
        let entries = [
            LogEntry(ts: date(9), bundleId: "signal", app: "Signal", kind: .launch, reason: "r"),
            LogEntry(ts: date(10), bundleId: "signal", app: "Signal", kind: .cancelled),
            LogEntry(ts: date(11), bundleId: "slack", app: "Slack", kind: .switch, reason: "r"),
            LogEntry(ts: date(day: 13, 11), bundleId: "signal", app: "Signal", kind: .expired, reason: "r"),
        ]
        XCTAssertEqual(reasonsToday(entries, bundleId: "signal", now: date(12), calendar: utc), 1)
        XCTAssertEqual(reasonsToday(entries, now: date(12), calendar: utc), 2)
    }

    func testOrdinal() {
        XCTAssertEqual([1, 2, 3, 4, 11, 12, 13, 21, 102, 111].map(ordinal),
                       ["1st", "2nd", "3rd", "4th", "11th", "12th", "13th", "21st", "102nd", "111th"])
    }
}

final class SiteTests: XCTestCase {
    func testSiteHostFromTypedInput() {
        XCTAssertEqual(siteHost("https://mail.google.com/mail/u/0/#inbox"), "mail.google.com")
        XCTAssertEqual(siteHost("  Mail.Google.com "), "mail.google.com")
        XCTAssertEqual(siteHost("www.youtube.com/feed"), "youtube.com")
        XCTAssertEqual(siteHost("http://localhost:8080/x"), "localhost")
        XCTAssertNil(siteHost(""))
        XCTAssertNil(siteHost("gmail"))
    }

    private let signal = GatedApp(bundleId: "org.whispersystems.signal-desktop", name: "Signal", path: "/Applications/Signal.app")

    func testIsSite() {
        XCTAssertFalse(signal.isSite)
        XCTAssertTrue(GatedApp(bundleId: "mail.google.com", name: "Gmail", path: "https://mail.google.com").isSite)
    }

    func testWebAppMatchesSiteAndSubdomainsMostSpecificFirst() {
        let gmail = GatedApp(bundleId: "mail.google.com", name: "Gmail", path: "https://mail.google.com")
        let google = GatedApp(bundleId: "google.com", name: "Google", path: "https://google.com")
        XCTAssertEqual(gatedSite(forWebAppURL: "https://mail.google.com/mail/u/0/", in: [signal, gmail]), gmail)
        XCTAssertNil(gatedSite(forWebAppURL: "https://docs.google.com/", in: [gmail]))
        XCTAssertNil(gatedSite(forWebAppURL: "https://notmail.google.com/", in: [gmail]))
        XCTAssertEqual(gatedSite(forWebAppURL: "https://docs.google.com/", in: [gmail, google]), google)
        XCTAssertEqual(gatedSite(forWebAppURL: "https://mail.google.com/", in: [google, gmail]), gmail)
        XCTAssertNil(gatedSite(forWebAppURL: "https://loop-habits-five.vercel.app/", in: [gmail, google]))
    }

    func testAddSite() {
        var entries = [signal]
        XCTAssertTrue(entries.addSite(name: " ", url: "mail.google.com/mail"))
        XCTAssertEqual(entries.last, GatedApp(bundleId: "mail.google.com", name: "mail.google.com", path: "https://mail.google.com/mail"))
        XCTAssertFalse(entries.addSite(name: "Again", url: "https://mail.google.com"))
        XCTAssertFalse(entries.addSite(name: "Bad", url: "gmail"))
        XCTAssertEqual(entries.count, 2)
    }

    func testEditRenamesAndChangesSiteURL() {
        var entries = [signal, GatedApp(bundleId: "mail.google.com", name: "Gmail", path: "https://mail.google.com")]
        XCTAssertTrue(entries.edit(id: signal.id, name: " Sig ", url: "https://ignored.com"))
        XCTAssertEqual(entries[0], GatedApp(bundleId: signal.bundleId, name: "Sig", path: signal.path))
        XCTAssertTrue(entries.edit(id: "mail.google.com", name: "", url: "youtube.com/feed"))
        XCTAssertEqual(entries[1], GatedApp(bundleId: "youtube.com", name: "Gmail", path: "https://youtube.com/feed"))
        XCTAssertTrue(entries.edit(id: "youtube.com", name: "YouTube", url: "https://youtube.com"), "same host is fine")
        XCTAssertEqual(entries[1].name, "YouTube")
    }

    func testEditRejectsBadOrTakenURL() {
        var entries = [
            GatedApp(bundleId: "mail.google.com", name: "Gmail", path: "https://mail.google.com"),
            GatedApp(bundleId: "youtube.com", name: "YouTube", path: "https://youtube.com"),
        ]
        let before = entries
        XCTAssertFalse(entries.edit(id: "youtube.com", name: "X", url: "mail.google.com"))
        XCTAssertFalse(entries.edit(id: "youtube.com", name: "X", url: "nope"))
        XCTAssertFalse(entries.edit(id: "gone.com", name: "X"))
        XCTAssertEqual(entries, before)
    }
}

private extension Data {
    func append(to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: self)
    }
}
