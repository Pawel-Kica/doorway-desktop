import DoorwayDesktopCore
import XCTest

final class CycleTests: XCTestCase {
    private enum Tab: CaseIterable { case focus, zone, music, sessions }

    func testStepsForwardAndBack() {
        XCTAssertEqual(Tab.focus.stepped(by: 1), .zone)
        XCTAssertEqual(Tab.zone.stepped(by: 1), .music)
        XCTAssertEqual(Tab.music.stepped(by: -1), .zone)
    }

    func testWrapsAtBothEnds() {
        XCTAssertEqual(Tab.sessions.stepped(by: 1), .focus)
        XCTAssertEqual(Tab.focus.stepped(by: -1), .sessions)
    }
}
