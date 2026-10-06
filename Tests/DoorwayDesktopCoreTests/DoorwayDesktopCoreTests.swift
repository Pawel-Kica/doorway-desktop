import XCTest
@testable import DoorwayDesktopCore

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

    func testEndOfWindow() {
        let day = Schedule(days: [2], from: 8 * 60, to: 19 * 60)
        XCTAssertEqual(day.end(of: date(9), calendar: utc), date(19))
        XCTAssertNil(day.end(of: date(20), calendar: utc))
        // 18:00-10:00: before midnight it ends tomorrow, after midnight today.
        let night = Schedule(days: [2], from: 18 * 60, to: 10 * 60)
        XCTAssertEqual(night.end(of: date(20), calendar: utc), date(day: 15, 10))
        XCTAssertEqual(night.end(of: date(day: 15, 3), calendar: utc), date(day: 15, 10))
        // All day Mon+Tue merges into one window ending Wednesday 00:00. Every day all day never ends.
        XCTAssertEqual(Schedule(days: [2, 3]).end(of: date(12), calendar: utc), date(day: 16, 0))
        XCTAssertNil(Schedule().end(of: date(12), calendar: utc))
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

    func testStopEndsATimerEarly() {
        var timers = AppTimers()
        timers.start("a", minutes: 5, now: date(9))
        timers.stop("a")
        XCTAssertFalse(timers.isRunning("a", now: date(9)))
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

    func testCountdown() {
        XCTAssertEqual(countdown(192), "3:12")
        XCTAssertEqual(countdown(60), "1:00")
        XCTAssertEqual(countdown(0.4), "0:01")
        XCTAssertEqual(countdown(3599), "59:59")
        XCTAssertEqual(countdown(9660), "2:41:00")
    }
}

final class RulesTests: XCTestCase {
    private let signal = GatedApp(bundleId: "org.whispersystems.signal-desktop", name: "Signal", path: "/Applications/Signal.app")
    private let whatsapp = GatedApp(bundleId: "net.whatsapp.WhatsApp", name: "WhatsApp", path: "/Applications/WhatsApp.app")
    private let gmail = GatedApp(bundleId: "com.google.Gmail", name: "Gmail", path: "/Applications/Gmail.app")

    private lazy var messengers = Blocklist(name: "Messengers", entries: [signal, whatsapp])
    private lazy var mail = Blocklist(name: "Mail", entries: [gmail, signal])

    private func rules(_ sessions: [ScheduledSession], _ quick: [QuickSession] = []) -> Rules {
        Rules(blocklists: [messengers, mail], sessions: sessions, quickSessions: quick)
    }

    private func gated(_ sessions: [ScheduledSession], _ quick: [QuickSession] = [], at now: Date) -> [String] {
        rules(sessions, quick).gated(at: now, calendar: utc).map(\.bundleId)
    }

    func testOverlappingSessionsGateTheUnionOnce() {
        let workday = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2], from: 8 * 60, to: 19 * 60))
        let evening = ScheduledSession(blocklists: [mail.id], schedule: Schedule(days: [2], from: 17 * 60, to: 22 * 60))
        XCTAssertEqual(gated([workday, evening], at: date(9)), [signal.bundleId, whatsapp.bundleId])
        XCTAssertEqual(gated([workday, evening], at: date(18)), [signal.bundleId, whatsapp.bundleId, gmail.bundleId])
        XCTAssertEqual(gated([workday, evening], at: date(20)), [gmail.bundleId, signal.bundleId])
        XCTAssertEqual(gated([workday, evening], at: date(23)), [])
    }

    func testDisabledSessionGatesNothing() {
        let off = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(), enabled: false)
        XCTAssertEqual(gated([off], at: date(12)), [])
        XCTAssertEqual(rules([off]).activeSessions(at: date(12), calendar: utc), [])
    }

    func testQuickSessionGatesUntilItEnds() {
        let quick = QuickSession(blocklists: [mail.id], ends: date(15))
        XCTAssertEqual(gated([], [quick], at: date(12)), [gmail.bundleId, signal.bundleId])
        XCTAssertEqual(gated([], [quick], at: date(15)), [])
    }

    func testOvernightSessionGatesAfterMidnight() {
        let night = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2], from: 22 * 60, to: 7 * 60))
        XCTAssertEqual(gated([night], at: date(day: 15, 3)), [signal.bundleId, whatsapp.bundleId])
        XCTAssertEqual(gated([night], at: date(day: 15, 7)), [])
    }

    func testSuperLockIsASubsetOfGatedAndHasAnEnd() {
        let night = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2], from: 18 * 60, to: 10 * 60), superLock: true)
        let evening = ScheduledSession(blocklists: [mail.id], schedule: Schedule(days: [2], from: 17 * 60, to: 22 * 60))
        let locked = rules([night, evening]).superLocked(at: date(20), calendar: utc).map(\.bundleId)
        XCTAssertEqual(locked, [signal.bundleId, whatsapp.bundleId])
        XCTAssertEqual(gated([night, evening], at: date(20)), [signal.bundleId, whatsapp.bundleId, gmail.bundleId])
        XCTAssertEqual(rules([night, evening]).superLocked(at: date(12), calendar: utc), [])
        XCTAssertEqual(rules([night, evening]).frozenBlocklists(at: date(20), calendar: utc), [messengers.id])
        XCTAssertEqual(rules([night]).superLockEnd(signal.bundleId, at: date(20), calendar: utc), date(day: 15, 10))
        // Two locks on the same app: the later end wins, and a never-ending one wins over both.
        let late = ScheduledSession(blocklists: [mail.id], schedule: Schedule(days: [2], from: 18 * 60, to: 12 * 60), superLock: true)
        XCTAssertEqual(rules([night, late]).superLockEnd(signal.bundleId, at: date(20), calendar: utc), date(day: 15, 12))
        let always = ScheduledSession(blocklists: [mail.id], schedule: Schedule(), superLock: true)
        XCTAssertNil(rules([night, always]).superLockEnd(signal.bundleId, at: date(20), calendar: utc))
    }

    func testDisabledOrOffSuperLockIsNotFrozen() {
        let off = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(), enabled: false, superLock: true)
        XCTAssertEqual(rules([off]).superLockedSessions(at: date(12), calendar: utc), [])
        XCTAssertEqual(rules([off]).frozenBlocklists(at: date(12), calendar: utc), [])
    }

    func testSessionsSavedBeforeSuperLockDecode() throws {
        let old = """
        [{"enabled":true,"id":"72F51428-5762-416F-9AAE-4B79C94EAF97","blocklists":[],"schedule":{"to":0,"from":0,"days":[1]}}]
        """
        let sessions = try JSONDecoder().decode([ScheduledSession].self, from: Data(old.utf8))
        XCTAssertEqual(sessions.count, 1)
        XCTAssertFalse(sessions[0].superLock)
        XCTAssertEqual(sessions[0].minutesPerReason, 5)
    }

    func testEveryEntryIsUniqueByBundleId() {
        XCTAssertEqual(rules([]).everyEntry.map(\.bundleId), [signal.bundleId, whatsapp.bundleId, gmail.bundleId])
        XCTAssertEqual(rules([]).entry(gmail.bundleId), gmail)
        XCTAssertNil(rules([]).entry("com.apple.Safari"))
        XCTAssertNil(rules([]).entry(nil))
    }

    func testNamesFollowSettingsOrder() {
        XCTAssertEqual(rules([]).names([mail.id, messengers.id]), "Messengers, Mail")
        XCTAssertEqual(rules([]).names([]), "No blocklist")
    }

    func testAccess() {
        let day = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2], from: 8 * 60, to: 19 * 60))
        let night = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2], from: 19 * 60, to: 8 * 60), superLock: true)
        let rules = rules([day, night])
        var timers = AppTimers()
        XCTAssertEqual(rules.access(signal.bundleId, timers: timers, at: date(12), calendar: utc), .ask)
        XCTAssertEqual(rules.access(gmail.bundleId, timers: timers, at: date(12), calendar: utc), .open, "no session gates Mail")
        XCTAssertEqual(rules.access("com.apple.Safari", timers: timers, at: date(12), calendar: utc), .open)
        timers.start(signal.bundleId, minutes: 5, now: date(12))
        XCTAssertEqual(rules.access(signal.bundleId, timers: timers, at: date(12, 4), calendar: utc), .open, "timer runs")
        XCTAssertEqual(rules.access(signal.bundleId, timers: timers, at: date(12, 5), calendar: utc), .ask, "timer ran out")
        timers.start(signal.bundleId, minutes: 5, now: date(20))
        XCTAssertEqual(rules.access(signal.bundleId, timers: timers, at: date(20), calendar: utc), .lock, "super lock wins over a timer")
    }

    func testMinutesPerReasonIsTheShortestActiveSession() {
        let day = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2], from: 8 * 60, to: 19 * 60),
                                   minutesPerReason: 10)
        let noon = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2], from: 12 * 60, to: 13 * 60),
                                    minutesPerReason: 3)
        let mailDay = ScheduledSession(blocklists: [mail.id], schedule: Schedule(days: [2], from: 8 * 60, to: 19 * 60),
                                       minutesPerReason: 1)
        let rules = rules([day, noon, mailDay])
        XCTAssertEqual(rules.minutesPerReason(whatsapp.bundleId, at: date(10), calendar: utc), 10)
        XCTAssertEqual(rules.minutesPerReason(whatsapp.bundleId, at: date(12), calendar: utc), 3, "overlap takes the shorter")
        XCTAssertEqual(rules.minutesPerReason(signal.bundleId, at: date(10), calendar: utc), 1, "Signal is in Mail too")
        XCTAssertEqual(rules.minutesPerReason(whatsapp.bundleId, at: date(20), calendar: utc), 5, "nothing on: the default")
        let quick = self.rules([], [QuickSession(blocklists: [messengers.id], ends: date(15))])
        XCTAssertEqual(quick.minutesPerReason(signal.bundleId, at: date(10), calendar: utc), 5, "quick sessions use the default")
    }

    func testDeletingBlocklistCleansSessions() {
        let lists = [messengers, mail]
        let sessions = [ScheduledSession(blocklists: [messengers.id, mail.id], schedule: Schedule()),
                        ScheduledSession(blocklists: [mail.id], schedule: Schedule())]
        let quick = [QuickSession(blocklists: [mail.id], ends: date(15)),
                     QuickSession(blocklists: [mail.id, messengers.id], ends: date(15))]
        var rules = Rules(blocklists: lists, sessions: sessions, quickSessions: quick)
        rules.deleteBlocklist(mail.id)
        XCTAssertEqual(rules.blocklists, [messengers])
        XCTAssertEqual(rules.sessions.map(\.blocklists), [[messengers.id], []], "an emptied session stays, to pick new lists")
        XCTAssertEqual(rules.quickSessions.map(\.blocklists), [[messengers.id]], "an emptied quick session ends")
    }

    private func split(_ rules: Rules) -> ([Blocklist], [ScheduledSession]) {
        XCTAssertEqual(rules.quickSessions, [])
        return (rules.blocklists, rules.sessions)
    }

    func testMigratesOldScheduleIntoOneBlocklistAndSession() {
        let (lists, sessions) = split(.migrated(gatedApps: [signal, gmail], scheduleDays: [2, 3], from: 8 * 60, to: 19 * 60))
        XCTAssertEqual(lists.map(\.name), ["Distractions"])
        XCTAssertEqual(lists[0].entries, [signal, gmail])
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].blocklists, [lists[0].id])
        XCTAssertEqual(sessions[0].schedule, Schedule(days: [2, 3], from: 8 * 60, to: 19 * 60))
        XCTAssertTrue(sessions[0].enabled)
    }

    func testMigrationWithoutOldKeysIsEveryDayAllDay() {
        let (lists, sessions) = split(.migrated(gatedApps: [], scheduleDays: nil, from: 0, to: 0))
        XCTAssertEqual(lists[0].entries, [])
        XCTAssertEqual(sessions[0].schedule, Schedule())
    }

    func testSettingsRoundTripAsJSON() throws {
        let session = ScheduledSession(blocklists: [messengers.id], schedule: Schedule(days: [2, 6], from: 480, to: 1140), superLock: true)
        let data = try JSONEncoder().encode([session])
        XCTAssertEqual(try JSONDecoder().decode([ScheduledSession].self, from: data), [session])
        XCTAssertEqual(try JSONDecoder().decode([Blocklist].self, from: JSONEncoder().encode([messengers])), [messengers])
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

final class GatedAppTests: XCTestCase {
    private let signal = GatedApp(bundleId: "org.whispersystems.signal-desktop", name: "Signal", path: "/Applications/Signal.app")

    func testRenameTrimsAndIgnoresEmptyOrMissing() {
        var entries = [signal]
        entries.rename(id: signal.id, to: " Sig ")
        XCTAssertEqual(entries[0], GatedApp(bundleId: signal.bundleId, name: "Sig", path: signal.path))
        entries.rename(id: signal.id, to: "  ")
        XCTAssertEqual(entries[0].name, "Sig")
        entries.rename(id: "gone", to: "X")
        XCTAssertEqual(entries.count, 1)
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

final class SessionRowTests: XCTestCase {
    private let messengers = UUID()

    func testNextStart() {
        let day = Schedule(days: [2], from: 10 * 60, to: 18 * 60)
        XCTAssertEqual(day.nextStart(after: date(8), calendar: utc), date(10))
        XCTAssertEqual(day.nextStart(after: date(20), calendar: utc), date(day: 21, 10), "next Monday")
        XCTAssertEqual(Schedule(days: Set(2...6), from: 10 * 60, to: 18 * 60).nextStart(after: date(day: 18, 19), calendar: utc),
                       date(day: 21, 10), "Friday evening waits for Monday")
        XCTAssertEqual(Schedule(from: 18 * 60, to: 10 * 60).nextStart(after: date(12), calendar: utc), date(18))
        XCTAssertEqual(Schedule(days: [3], from: 9 * 60, to: 9 * 60).nextStart(after: date(12), calendar: utc), date(day: 15, 0),
                       "all day starts at midnight")
        XCTAssertNil(Schedule(days: []).nextStart(after: date(12), calendar: utc))
    }

    func testDaysSummary() {
        var english = utc
        english.locale = Locale(identifier: "en_US_POSIX")
        XCTAssertEqual(Schedule().daysSummary(calendar: english), "Every day")
        XCTAssertEqual(Schedule(days: Set(2...6)).daysSummary(calendar: english), "Weekdays")
        XCTAssertEqual(Schedule(days: [1, 7]).daysSummary(calendar: english), "Weekends")
        XCTAssertEqual(Schedule(days: []).daysSummary(calendar: english), "No days")
        XCTAssertEqual(Schedule(days: [6, 1, 2, 4]).daysSummary(calendar: english), "Mon, Wed, Fri, Sun")
    }

    func testTimeLeft() {
        XCTAssertEqual(timeLeft(0), "0 min")
        XCTAssertEqual(timeLeft(20), "1 min", "rounds up")
        XCTAssertEqual(timeLeft(45 * 60), "45 min")
        XCTAssertEqual(timeLeft(3600), "1 h")
        XCTAssertEqual(timeLeft(13 * 3600 + 34 * 60 + 20), "13 h 35 min")
        XCTAssertEqual(timeLeft(48 * 3600), "2 d")
        XCTAssertEqual(timeLeft(51 * 3600), "2 d 3 h")
    }

    func testParseClock() {
        XCTAssertEqual(parseClock("18:00"), 18 * 60)
        XCTAssertEqual(parseClock(" 8:05 "), 8 * 60 + 5)
        XCTAssertEqual(parseClock("18.30"), 18 * 60 + 30)
        XCTAssertEqual(parseClock("9"), 9 * 60)
        XCTAssertEqual(parseClock("0:00"), 0)
        XCTAssertEqual(parseClock("23:59"), 23 * 60 + 59)
        for typed in ["19:3", "19:", "24:00", "12:60", "", "ab", "1:2:3", "-1:00", "+8:00", "123", "8:05 PM"] {
            XCTAssertNil(parseClock(typed), typed)
        }
        XCTAssertEqual(clockText(8 * 60 + 5), "08:05")
        XCTAssertEqual(parseClock(clockText(19 * 60 + 30)), 19 * 60 + 30)
    }

    func testStatus() {
        let night = ScheduledSession(blocklists: [messengers], schedule: Schedule(from: 18 * 60, to: 10 * 60), superLock: true)
        XCTAssertEqual(night.status(at: date(20), calendar: utc), .on(until: date(day: 15, 10)))
        XCTAssertEqual(night.status(at: date(12), calendar: utc), .starts(date(18)))
        let day = ScheduledSession(blocklists: [messengers], schedule: Schedule(days: [2], from: 10 * 60, to: 18 * 60))
        XCTAssertEqual(day.status(at: date(20), calendar: utc), .starts(date(day: 21, 10)))
        XCTAssertEqual(ScheduledSession(blocklists: [], schedule: Schedule()).status(at: date(12), calendar: utc), .alwaysOn)
        XCTAssertEqual(ScheduledSession(blocklists: [], schedule: Schedule(), enabled: false).status(at: date(12), calendar: utc), .off)
        XCTAssertEqual(ScheduledSession(blocklists: [], schedule: Schedule(days: [])).status(at: date(12), calendar: utc), .off)
    }

    func testSessionTitleIsItsNameOrItsBlocklists() {
        let list = Blocklist(name: "Messengers")
        var session = ScheduledSession(blocklists: [list.id], schedule: Schedule(from: 10 * 60, to: 18 * 60))
        let rules = Rules(blocklists: [list], sessions: [session])
        XCTAssertEqual(rules.title(session), "Messengers")
        session.name = "  "
        XCTAssertEqual(rules.title(session), "Messengers")
        session.name = " Deep work "
        XCTAssertEqual(rules.title(session), "Deep work")
    }

    func testSessionSavedBeforeNamesDecodesUnnamed() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","blocklists":[],"schedule":{"days":[2],"from":600,"to":1080},"enabled":true,"superLock":true}"#
        let session = try JSONDecoder().decode(ScheduledSession.self, from: Data(json.utf8))
        XCTAssertEqual(session.name, "")
        XCTAssertTrue(session.superLock)
    }

    func testDuplicateSessionGoesRightBelowDisabled() {
        let night = ScheduledSession(blocklists: [messengers], schedule: Schedule(from: 18 * 60, to: 10 * 60), superLock: true)
        let day = ScheduledSession(blocklists: [messengers], schedule: Schedule(from: 10 * 60, to: 18 * 60))
        var rules = Rules(sessions: [night, day])
        let id = rules.duplicateSession(night.id)
        XCTAssertEqual(rules.sessions.map(\.id), [night.id, id, day.id])
        var copy = rules.sessions[1]
        XCTAssertNotEqual(copy.id, night.id)
        XCTAssertFalse(copy.enabled)
        copy.id = night.id
        copy.enabled = true
        XCTAssertEqual(copy, night, "same blocklists, schedule and super lock")
        XCTAssertNil(rules.duplicateSession(UUID()))
        XCTAssertEqual(rules.sessions.count, 3)
    }
}
