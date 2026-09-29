import XCTest
@testable import SimpleBlockCore

private let start = Date(timeIntervalSince1970: 1_790_000_000)
private let session = FocusSession(started: start, ends: start.addingTimeInterval(2 * 3600))
private let obsidian = GatedApp(bundleId: "md.obsidian", name: "Obsidian", path: "/Applications/Obsidian.app")
private let todoist = GatedApp(bundleId: "com.todoist.mac.Todoist", name: "Todoist", path: "/Applications/Todoist.app")
private let slack = GatedApp(bundleId: "com.tinyspeck.slackmacgap", name: "Slack", path: "/Applications/Slack.app")
private let notes = GatedApp(bundleId: "com.apple.Notes", name: "Notes", path: "/System/Applications/Notes.app")

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

    func testAllowedIsPickedListsUnique() {
        let deepWork = Allowlist(name: "Deep work", entries: [obsidian, todoist])
        let writing = Allowlist(name: "Writing", entries: [todoist, notes])
        let chat = Allowlist(name: "Chat", entries: [slack])
        let rules = FocusRules(allowlists: [deepWork, writing, chat], picked: [deepWork.id, writing.id])
        XCTAssertEqual(rules.allowed, [obsidian, todoist, notes], "Chat isn't picked, Todoist counts once")
        XCTAssertFalse(session.hides("md.obsidian", allowed: rules.allowed, at: minutes(10)))
        XCTAssertTrue(session.hides("com.tinyspeck.slackmacgap", allowed: rules.allowed, at: minutes(10)))
    }

    func testPickedIdsOfMissingListsAreIgnored() {
        XCTAssertEqual(FocusRules(picked: [UUID()]).allowed, [])
    }

    func testEditsApplyLive() {
        let deepWork = Allowlist(name: "Deep work", entries: [obsidian])
        var rules = FocusRules(allowlists: [deepWork], picked: [deepWork.id])
        rules.allowlists[0].entries.add([todoist])
        XCTAssertEqual(rules.allowed, [obsidian, todoist])
        rules.picked = []
        XCTAssertEqual(rules.allowed, [])
    }

    func testNamesArePickedListsWithApps() {
        let deepWork = Allowlist(name: "Deep work", entries: [obsidian, todoist])
        let empty = Allowlist(name: "Empty")
        let chat = Allowlist(name: "Chat", entries: [slack])
        let rules = FocusRules(allowlists: [deepWork, empty, chat], picked: [deepWork.id, empty.id, chat.id])
        XCTAssertEqual(rules.names, "Deep work, Chat", "Empty lists are left out")
        XCTAssertEqual(FocusRules().names, "")
    }

    func testDeletingAllowlistDropsItsPick() {
        let deepWork = Allowlist(name: "Deep work", entries: [obsidian])
        let chat = Allowlist(name: "Chat", entries: [slack])
        var rules = FocusRules(allowlists: [deepWork, chat], picked: [deepWork.id, chat.id])
        rules.deleteAllowlist(deepWork.id)
        XCTAssertEqual(rules.allowlists, [chat])
        XCTAssertEqual(rules.picked, [chat.id])
        XCTAssertEqual(rules.allowed, [slack])
    }

    func testMigrationMovesOwnAppsIntoAPickedList() {
        let rules = FocusRules.migrated(apps: [obsidian, todoist])
        XCTAssertEqual(rules.allowlists.map(\.name), ["Deep work"])
        XCTAssertEqual(rules.picked, Set(rules.allowlists.map(\.id)))
        XCTAssertEqual(rules.allowed, [obsidian, todoist])
        XCTAssertEqual(FocusRules.migrated(apps: []), FocusRules(), "Nothing to move, no list")
    }

    func testAddSkipsAppsAlreadyIn() {
        var apps = [obsidian]
        apps.add([todoist, obsidian, todoist])
        XCTAssertEqual(apps, [obsidian, todoist])
    }

    func testLeavingIsGoneOnlyWhenHiddenOutOfFrontAndOffScreen() {
        let app = LeavingApp(at: start)
        let soon = start.addingTimeInterval(focusCoverMinimum)
        XCTAssertEqual(app.state(active: false, hidden: true, onScreen: false, at: soon), .gone)
        XCTAssertEqual(app.state(active: false, hidden: true, onScreen: false, at: start.addingTimeInterval(0.03)), .leaving,
                       "Covered a moment at least, its windows may still be coming up")
        XCTAssertEqual(app.state(active: true, hidden: true, onScreen: false, at: soon), .leaving, "Still in front")
        XCTAssertEqual(app.state(active: false, hidden: false, onScreen: false, at: soon), .leaving, "Hide not done")
        XCTAssertEqual(app.state(active: false, hidden: true, onScreen: true, at: soon), .leaving,
                       "Marked hidden, windows still up")
        XCTAssertEqual(app.state(active: false, hidden: true, onScreen: false, at: minutes(5)), .gone)
    }

    func testLeavingGetsStuckAfterTheLastAttempt() {
        let app = LeavingApp(at: start)
        XCTAssertEqual(app.state(active: true, hidden: false, onScreen: true,
                                 at: start.addingTimeInterval(focusCoverLimit - 0.01)), .leaving)
        XCTAssertEqual(app.state(active: true, hidden: false, onScreen: true,
                                 at: start.addingTimeInterval(focusCoverLimit)), .stuck)
        XCTAssertEqual(app.state(active: false, hidden: true, onScreen: true, at: start.addingTimeInterval(5)), .stuck,
                       "A window that stays up while hidden")
    }

    func testAttemptsInARowKeepItLeavingUpToTheStreakLimit() {
        var app = LeavingApp(at: start)
        // Clicking it in the Dock every second.
        for second in 1..<Int(focusCoverStreakLimit) {
            let now = start.addingTimeInterval(TimeInterval(second))
            app.attempted(at: now)
            XCTAssertEqual(app.state(active: true, hidden: false, onScreen: true, at: now.addingTimeInterval(0.5)), .leaving)
        }
        let end = start.addingTimeInterval(focusCoverStreakLimit)
        app.attempted(at: end)
        XCTAssertTrue(app.isStuck(at: end), "An app that keeps bringing itself back can't hold the backdrop up")
        XCTAssertEqual(app.first, start)
    }

    func testForgottenOnlyAfterBeingGoneAWhile() {
        let app = LeavingApp(at: start)
        let gone = (active: false, hidden: true, onScreen: false)
        XCTAssertFalse(app.isOver(active: gone.active, hidden: gone.hidden, onScreen: gone.onScreen,
                                  at: start.addingTimeInterval(1)), "Gone, but a quick re-attempt is the same row")
        XCTAssertTrue(app.isOver(active: gone.active, hidden: gone.hidden, onScreen: gone.onScreen,
                                 at: start.addingTimeInterval(focusCoverLimit)))
        XCTAssertFalse(app.isOver(active: true, hidden: false, onScreen: true, at: minutes(5)), "Stuck and still up")
    }

    func testAnAppThatKeepsComingBackHitsTheStreakLimit() {
        var app = LeavingApp(at: start)
        // Hides fine, then brings itself back every second.
        for second in 1..<Int(focusCoverStreakLimit) {
            let now = start.addingTimeInterval(TimeInterval(second))
            XCTAssertFalse(app.isOver(active: false, hidden: true, onScreen: false, at: now))
            app.attempted(at: now)
        }
        XCTAssertTrue(app.isStuck(at: start.addingTimeInterval(focusCoverStreakLimit)))
    }

    func testCoversUnlessHiddenAsFocusStarted() {
        XCTAssertTrue(LeavingApp(at: start).covers)
        var quiet = LeavingApp(at: start, covers: false)
        quiet.attempted(at: start.addingTimeInterval(1))
        XCTAssertFalse(quiet.covers)
    }

    func testSlippedPastFocus() {
        XCTAssertTrue(slippedPastFocus(active: true, hidden: false, onScreen: true))
        XCTAssertTrue(slippedPastFocus(active: true, hidden: true, onScreen: false), "In front counts even when marked hidden")
        XCTAssertTrue(slippedPastFocus(active: false, hidden: false, onScreen: true))
        XCTAssertFalse(slippedPastFocus(active: false, hidden: false, onScreen: false), "Running without a window")
        XCTAssertFalse(slippedPastFocus(active: false, hidden: true, onScreen: true), "A window that stays up while hidden")
    }

    func testMinuteCountdownRoundsUp() {
        XCTAssertEqual(minuteCountdown(102 * 60), "1:42")
        XCTAssertEqual(minuteCountdown(102 * 60 - 30), "1:42")
        XCTAssertEqual(minuteCountdown(25 * 60), "0:25")
        XCTAssertEqual(minuteCountdown(1), "0:01")
        XCTAssertEqual(minuteCountdown(4 * 3600), "4:00")
    }
}
