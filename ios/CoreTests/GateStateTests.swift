import SimpleBlockMobileCore
import XCTest

final class GateStateTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second))!
    }

    func testFifthOpenIsShortSixthIsLong() {
        var state = GateState()
        for i in 0..<4 { state.open(.signal, reason: "r", now: date(28, 9, i), calendar: calendar) }
        let now = date(28, 10)
        XCTAssertEqual(state.opensToday(now: now, calendar: calendar), 4)
        XCTAssertEqual(state.requiredWords(now: now, calendar: calendar), 5, "5th open still short")
        state.open(.signal, reason: "r", now: now, calendar: calendar)
        XCTAssertEqual(state.shortLeft(now: now, calendar: calendar), 0)
        XCTAssertEqual(state.requiredWords(now: now, calendar: calendar), 30, "6th open needs a long one")
    }

    func testMidnightResetsTheCount() {
        var state = GateState()
        for i in 0..<5 { state.open(.signal, reason: "r", now: date(27, 23, i), calendar: calendar) }
        XCTAssertEqual(state.requiredWords(now: date(27, 23, 59, 59), calendar: calendar), 30)
        XCTAssertEqual(state.opensToday(now: date(28, 0), calendar: calendar), 0)
        XCTAssertEqual(state.requiredWords(now: date(28, 0), calendar: calendar), 5)
    }

    func testResistedEntriesDontCount() {
        var state = GateState()
        for i in 0..<6 { state.resist(.signal, now: date(28, 9, i), calendar: calendar) }
        let now = date(28, 10)
        XCTAssertEqual(state.opensToday(now: now, calendar: calendar), 0)
        XCTAssertEqual(state.resistedToday(now: now, calendar: calendar), 6)
        XCTAssertEqual(state.requiredWords(now: now, calendar: calendar), 5)
        XCTAssertFalse(state.isUnlocked(.signal, now: now))
    }

    func testUnlockWindowBoundary() {
        var state = GateState()
        let opened = date(28, 10)
        state.open(.signal, reason: "r", now: opened, calendar: calendar)
        XCTAssertTrue(state.isUnlocked(.signal, now: opened))
        XCTAssertTrue(state.isUnlocked(.signal, now: date(28, 10, 4, 59)))
        XCTAssertFalse(state.isUnlocked(.signal, now: date(28, 10, 5)), "locked again exactly at unlockMinutes")
    }

    func testUnlockIsPerApp() {
        var state = GateState()
        state.open(.signal, reason: "r", now: date(28, 10), calendar: calendar)
        XCTAssertTrue(state.isUnlocked(.signal, now: date(28, 10, 1)))
        XCTAssertFalse(state.isUnlocked(.messages, now: date(28, 10, 1)))
    }

    func testZeroShortPerDayMeansAlwaysLong() {
        var state = GateState()
        state.settings.shortPerDay = 0
        XCTAssertEqual(state.shortLeft(now: date(28, 10), calendar: calendar), 0)
        XCTAssertEqual(state.requiredWords(now: date(28, 10), calendar: calendar), 30)
    }

    func testTrimsEntriesOlderThan30Days() {
        var state = GateState()
        state.open(.signal, reason: "old", now: date(28, 10).addingTimeInterval(-31 * 86400), calendar: calendar)
        state.open(.signal, reason: "recent", now: date(28, 10).addingTimeInterval(-29 * 86400), calendar: calendar)
        state.open(.signal, reason: "new", now: date(28, 10), calendar: calendar)
        XCTAssertEqual(state.entries.map(\.reason), ["recent", "new"])
    }

    func testWordCount() {
        XCTAssertEqual(wordCount(""), 0)
        XCTAssertEqual(wordCount("   \n "), 0)
        XCTAssertEqual(wordCount("reply to mom"), 3)
        XCTAssertEqual(wordCount("  reply\tto\nmom  "), 3)
    }

    func testCodableRoundTrip() throws {
        var state = GateState()
        state.settings.longWords = 40
        state.open(.signal, reason: "reply to mom", now: date(28, 10), calendar: calendar)
        state.resist(.x, now: date(28, 11), calendar: calendar)
        let decoded = try JSONDecoder().decode(GateState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded, state)
    }
}
