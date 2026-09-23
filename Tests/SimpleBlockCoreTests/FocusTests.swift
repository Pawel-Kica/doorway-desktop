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

    func testAllowedIsPickedListsThenOwnAppsUnique() {
        let deepWork = Allowlist(name: "Deep work", entries: [obsidian, todoist])
        let chat = Allowlist(name: "Chat", entries: [slack])
        let rules = FocusRules(allowlists: [deepWork, chat], picked: [deepWork.id], apps: [todoist, notes])
        XCTAssertEqual(rules.allowed, [obsidian, todoist, notes], "Chat isn't picked, Todoist counts once")
        XCTAssertFalse(session.hides("md.obsidian", allowed: rules.allowed, at: minutes(10)))
        XCTAssertTrue(session.hides("com.tinyspeck.slackmacgap", allowed: rules.allowed, at: minutes(10)))
    }

    func testPickedIdsOfMissingListsAreIgnored() {
        XCTAssertEqual(FocusRules(picked: [UUID()], apps: [notes]).allowed, [notes])
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

    func testNamesAreListsFirstThenOwnAppsOutsideThem() {
        let deepWork = Allowlist(name: "Deep work", entries: [obsidian, todoist])
        let empty = Allowlist(name: "Empty")
        let chat = Allowlist(name: "Chat", entries: [slack])
        let rules = FocusRules(allowlists: [deepWork, empty, chat], picked: [deepWork.id, empty.id], apps: [todoist, notes])
        XCTAssertEqual(rules.names, "Deep work, Notes", "Empty lists and apps already in a picked list are left out")
        XCTAssertEqual(FocusRules(apps: [obsidian, todoist]).names, "Obsidian, Todoist")
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
        XCTAssertEqual(rules.apps, [])
        XCTAssertEqual(rules.allowed, [obsidian, todoist])
        XCTAssertEqual(FocusRules.migrated(apps: []), FocusRules(), "Nothing to move, no list")
    }

    func testAddSkipsAppsAlreadyIn() {
        var apps = [obsidian]
        apps.add([todoist, obsidian, todoist])
        XCTAssertEqual(apps, [obsidian, todoist])
    }

    func testMinuteCountdownRoundsUp() {
        XCTAssertEqual(minuteCountdown(102 * 60), "1:42")
        XCTAssertEqual(minuteCountdown(102 * 60 - 30), "1:42")
        XCTAssertEqual(minuteCountdown(25 * 60), "0:25")
        XCTAssertEqual(minuteCountdown(1), "0:01")
        XCTAssertEqual(minuteCountdown(4 * 3600), "4:00")
    }
}
