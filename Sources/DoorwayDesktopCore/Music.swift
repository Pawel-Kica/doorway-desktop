import Foundation

/// One track: the built-in Lofi Jazz mix or an audio file added in Settings. Every track is a file in the app's
/// Music folder; the built-in one gets there by downloading it.
public struct Track: Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    /// File name inside the Music folder, e.g. "lofi-jazz.mp3".
    public var file: String

    public init(id: String, name: String, file: String) {
        self.id = id
        self.name = name
        self.file = file
    }

    public static let lofiJazz = Track(id: "lofi-jazz", name: "Lofi Jazz", file: "lofi-jazz.mp3")
    public var isBuiltIn: Bool { id == Track.lofiJazz.id }
}

/// The music settings: every track, the Active ones (played in turn with Play next) and what a track's end does.
public struct MusicLibrary: Codable, Equatable {
    public var tracks: [Track]
    /// IDs of the Active tracks, in play order.
    public var active: [String]
    /// A track that ends starts over instead of going to the next Active one.
    public var repeatTrack: Bool

    public init(tracks: [Track], active: [String], repeatTrack: Bool) {
        self.tracks = tracks
        self.active = active
        self.repeatTrack = repeatTrack
    }

    /// First run: just Lofi Jazz, Active, Play next.
    public static let standard = MusicLibrary(tracks: [.lofiJazz], active: [Track.lofiJazz.id], repeatTrack: false)

    public var activeTracks: [Track] { active.compactMap { id in tracks.first { $0.id == id } } }
    /// Tracks outside Active, in the order they were added.
    public var otherTracks: [Track] { tracks.filter { !active.contains($0.id) } }

    /// What plays after `current` ends. Repeat, or no Active tracks: the same one. Play next: the Active track after
    /// it, wrapping around; a track outside Active goes to the first Active one.
    public func next(after current: String) -> String {
        let ids = activeTracks.map(\.id)
        guard !repeatTrack, let first = ids.first else { return current }
        guard let index = ids.firstIndex(of: current) else { return first }
        return ids[(index + 1) % ids.count]
    }

    /// Puts a track at the end of Active.
    public mutating func activate(_ id: String) {
        guard tracks.contains(where: { $0.id == id }), !active.contains(id) else { return }
        active.append(id)
    }

    /// Moves a track one spot up (-1) or down (+1) in Active then Library, read as one list. The last Active track
    /// goes down to the top of Library, the first Library track up to the end of Active. Past either end it stays put.
    public mutating func move(_ id: String, by offset: Int) {
        let others = otherTracks.map(\.id)
        if let index = active.firstIndex(of: id) {
            if active.indices.contains(index + offset) {
                active.swapAt(index, index + offset)
            } else if offset > 0 {
                deactivate(id)
                if let top = others.first { place(id, before: top) }
            }
        } else if let index = others.firstIndex(of: id) {
            if others.indices.contains(index + offset) {
                let neighbor = others[index + offset]
                offset < 0 ? place(id, before: neighbor) : place(neighbor, before: id)
            } else if offset < 0 {
                activate(id)
            }
        }
    }

    /// Puts track `id` right before track `other` in `tracks`, which sets Library's order.
    private mutating func place(_ id: String, before other: String) {
        guard let from = tracks.firstIndex(where: { $0.id == id }) else { return }
        let track = tracks.remove(at: from)
        tracks.insert(track, at: tracks.firstIndex { $0.id == other } ?? tracks.endIndex)
    }

    public mutating func deactivate(_ id: String) {
        active.removeAll { $0 == id }
    }

    /// Renames a track. An empty name keeps the old one.
    public mutating func rename(_ id: String, to name: String) {
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, let index = tracks.firstIndex(where: { $0.id == id }) else { return }
        tracks[index].name = typed
    }

    /// Drops a track and its Active spot. The built-in one stays.
    public mutating func remove(_ id: String) {
        guard id != Track.lofiJazz.id else { return }
        tracks.removeAll { $0.id == id }
        deactivate(id)
    }
}
