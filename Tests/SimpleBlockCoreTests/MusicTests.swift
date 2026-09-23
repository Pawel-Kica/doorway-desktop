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

    func testActivateAppendsInsertsAndMoves() {
        var music = library(active: [])
        music.activate("rain")
        music.activate("piano")
        XCTAssertEqual(music.active, ["rain", "piano"])
        music.activate("lofi-jazz", at: 0)
        XCTAssertEqual(music.active, ["lofi-jazz", "rain", "piano"])
        music.activate("lofi-jazz", at: 2)
        XCTAssertEqual(music.active, ["rain", "lofi-jazz", "piano"], "Moving down lands before the target")
        music.activate("piano", at: 0)
        XCTAssertEqual(music.active, ["piano", "rain", "lofi-jazz"])
        music.activate("gone")
        XCTAssertEqual(music.active, ["piano", "rain", "lofi-jazz"], "Unknown IDs are ignored")
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
