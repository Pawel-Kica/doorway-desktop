import XCTest
@testable import SimpleBlockCore

private let start = Date(timeIntervalSince1970: 1_790_000_000)
private let session = FocusSession(started: start, ends: start.addingTimeInterval(2 * 3600))
private let obsidian = GatedApp(bundleId: "md.obsidian", name: "Obsidian", path: "/Applications/Obsidian.app")
private let todoist = GatedApp(bundleId: "com.todoist.mac.Todoist", name: "Todoist", path: "/Applications/Todoist.app")

private func minutes(_ n: Double) -> Date { start.addingTimeInterval(n * 60) }

final class FocusTests: XCTestCase {
    func testHidesAppsOutsideAllowedWhileOn() {
        XCTAssertTrue(session.hides("com.t3tools.t3code", allowed: [obsidian, todoist], at: minutes(10)))
        XCTAssertTrue(session.hides("com.t3tools.t3code", allowed: [], at: minutes(10)))
    }

    func testAllowedAppsStayVisible() {
        XCTAssertFalse(session.hides("md.obsidian", allowed: [obsidian, todoist], at: minutes(10)))
        XCTAssertFalse(session.hides("com.todoist.mac.Todoist", allowed: [obsidian, todoist], at: minutes(10)))
    }

    func testFinderAndSimpleBlockAreAlwaysAllowed() {
        XCTAssertFalse(session.hides("com.apple.finder", allowed: [], at: minutes(10)))
        XCTAssertFalse(session.hides("com.pawel.simple-block", allowed: [obsidian], at: minutes(10)))
    }

    func testNilBundleIdIsLeftAlone() {
        XCTAssertFalse(session.hides(nil, allowed: [obsidian], at: minutes(10)))
    }

    func testEndedSessionHidesNothing() {
        XCTAssertTrue(session.isOn(at: minutes(119)))
        XCTAssertFalse(session.isOn(at: minutes(120)), "Off at its end")
        XCTAssertFalse(session.hides("com.t3tools.t3code", allowed: [obsidian], at: minutes(120)))
        XCTAssertFalse(session.hides("com.t3tools.t3code", allowed: [obsidian], at: minutes(500)))
    }

    func testRemaining() {
        XCTAssertEqual(session.remaining(at: minutes(18)), 102 * 60)
        XCTAssertEqual(session.remaining(at: minutes(200)), 0)
    }

    func testMinutesRunRoundsAndStopsAtEnd() {
        XCTAssertEqual(session.minutesRun(at: minutes(0.4)), 0)
        XCTAssertEqual(session.minutesRun(at: minutes(42.6)), 43)
        XCTAssertEqual(session.minutesRun(at: minutes(120)), 120)
        XCTAssertEqual(session.minutesRun(at: minutes(600)), 120, "Relaunched long after it ended")
    }

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(session)
        XCTAssertEqual(try JSONDecoder().decode(FocusSession.self, from: data), session)
    }

    func testDurationText() {
        XCTAssertEqual(durationText(25), "25 min")
        XCTAssertEqual(durationText(60), "1 h")
        XCTAssertEqual(durationText(90), "1 h 30 min")
        XCTAssertEqual(durationText(240), "4 h")
    }

    func testMinuteCountdownRoundsUp() {
        XCTAssertEqual(minuteCountdown(102 * 60), "1:42")
        XCTAssertEqual(minuteCountdown(102 * 60 - 30), "1:42")
        XCTAssertEqual(minuteCountdown(25 * 60), "0:25")
        XCTAssertEqual(minuteCountdown(1), "0:01")
        XCTAssertEqual(minuteCountdown(4 * 3600), "4:00")
    }
}
