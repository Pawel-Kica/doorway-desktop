import XCTest
@testable import SimpleBlockCore

private let rain = Track(id: "rain", name: "Rain", file: "rain.mp3")
private let piano = Track(id: "piano", name: "Piano", file: "piano.mp3")

private func library(active: [String], repeatTrack: Bool = false) -> MusicLibrary {
    MusicLibrary(tracks: [.lofiJazz, rain, piano], active: active, repeatTrack: repeatTrack)
}

final class MusicTests: XCTestCase {
    func testPlayNextGoesThroughActiveAndWraps() {
        let music = library(active: ["rain", "piano"])
        XCTAssertEqual(music.next(after: "rain"), "piano")
        XCTAssertEqual(music.next(after: "piano"), "rain")
    }

    func testTrackOutsideActiveGoesToFirstActive() {
        XCTAssertEqual(library(active: ["rain", "piano"]).next(after: "lofi-jazz"), "rain")
    }

    func testRepeatOrNoActiveRepeatsTheTrack() {
        XCTAssertEqual(library(active: ["rain", "piano"], repeatTrack: true).next(after: "rain"), "rain")
        XCTAssertEqual(library(active: []).next(after: "rain"), "rain")
        XCTAssertEqual(library(active: ["rain"]).next(after: "rain"), "rain", "One Active track loops")
    }

    func testActivateAppendsOnce() {
        var music = library(active: [])
        music.activate("rain")
        music.activate("piano")
        music.activate("rain")
        XCTAssertEqual(music.active, ["rain", "piano"])
        music.activate("gone")
        XCTAssertEqual(music.active, ["rain", "piano"], "Unknown IDs are ignored")
    }

    func testMoveStepsWithinActive() {
        var music = library(active: ["rain", "piano", "lofi-jazz"])
        music.move("piano", by: -1)
        XCTAssertEqual(music.active, ["piano", "rain", "lofi-jazz"])
        music.move("piano", by: -1)
        XCTAssertEqual(music.active, ["piano", "rain", "lofi-jazz"], "The first one can't go up")
        music.move("rain", by: 1)
        XCTAssertEqual(music.active, ["piano", "lofi-jazz", "rain"])
        music.move("rain", by: 1)
        XCTAssertEqual(music.active, ["piano", "lofi-jazz", "rain"], "The last one can't go down")
    }

    func testActiveAndOtherTracksSplitTheLibrary() {
        let music = library(active: ["piano", "lofi-jazz"])
        XCTAssertEqual(music.activeTracks.map(\.id), ["piano", "lofi-jazz"])
        XCTAssertEqual(music.otherTracks.map(\.id), ["rain"])
    }

    func testRemoveDropsTrackAndActiveSpotButKeepsBuiltIn() {
        var music = library(active: ["rain", "lofi-jazz"])
        music.remove("rain")
        XCTAssertEqual(music.tracks.map(\.id), ["lofi-jazz", "piano"])
        XCTAssertEqual(music.active, ["lofi-jazz"])
        music.remove("lofi-jazz")
        XCTAssertEqual(music.tracks.map(\.id), ["lofi-jazz", "piano"])
    }

    func testRenameKeepsOldNameWhenEmpty() {
        var music = library(active: [])
        music.rename("rain", to: "  Rain sounds ")
        music.rename("piano", to: "   ")
        XCTAssertEqual(music.tracks.map(\.name), ["Lofi Jazz", "Rain sounds", "Piano"])
    }
}
