import Foundation

/// Apps a focus session never hides: Finder and Simple Block itself.
public let alwaysAllowedInFocus: Set<String> = ["com.apple.finder", "com.pawel.simple-block"]

/// Allowlists have the blocklists' shape: a named list of apps, e.g. "Deep work". Focus uses the ones picked for it.
public typealias Allowlist = Blocklist

/// Everything that decides what focus allows: the allowlists and the ones picked for focus.
/// `allowed` is worked out on every call, so editing a list or the picks during a focus applies right away.
public struct FocusRules: Equatable {
    public var allowlists: [Allowlist]
    /// Allowlists focus uses, picked in the Focus tab. IDs of deleted lists are ignored.
    public var picked: Set<UUID>

    public init(allowlists: [Allowlist] = [], picked: Set<UUID> = []) {
        self.allowlists = allowlists
        self.picked = picked
    }

    /// Focus before allowlists had only its own apps. They become a picked allowlist "Deep work". No apps, no list.
    public static func migrated(apps: [GatedApp]) -> FocusRules {
        guard !apps.isEmpty else { return FocusRules() }
        let list = Allowlist(name: "Deep work", entries: apps)
        return FocusRules(allowlists: [list], picked: [list.id])
    }

    /// Picked allowlists in Settings order.
    public var pickedLists: [Allowlist] { allowlists.filter { picked.contains($0.id) } }

    /// What focus allows: the picked allowlists' apps, unique by bundle ID.
    public var allowed: [GatedApp] { unique(pickedLists.flatMap(\.entries)) }

    /// For toasts, the popover and the log, e.g. "Deep work, Chat": picked lists that hold apps.
    public var names: String {
        pickedLists.filter { !$0.entries.isEmpty }.map(\.name).joined(separator: ", ")
    }

    /// Deletes an allowlist and drops it from the picks.
    public mutating func deleteAllowlist(_ id: UUID) {
        allowlists.removeAll { $0.id == id }
        picked.remove(id)
    }
}

/// A running focus session: until `ends` only its allowed apps may come to the front, everything else gets hidden.
/// The allowed apps aren't stored here, they come from `FocusRules`, so editing them applies right away.
public struct FocusSession: Codable, Equatable {
    public var started: Date
    public var ends: Date

    public init(started: Date, ends: Date) {
        self.started = started
        self.ends = ends
    }

    public func isOn(at now: Date) -> Bool { ends > now }

    public func remaining(at now: Date) -> TimeInterval { max(0, ends.timeIntervalSince(now)) }

    /// Whole minutes it ran by `now`, rounded, never past its end. For the `focus` log entry.
    public func minutesRun(at now: Date) -> Int {
        Int((min(now, ends).timeIntervalSince(started) / 60).rounded())
    }

    /// Whether an app coming forward gets hidden: only while on, and only when it's neither allowed nor always allowed.
    /// An app without a bundle ID can't be told apart, so it's left alone.
    public func hides(_ bundleId: String?, allowed: [GatedApp], at now: Date) -> Bool {
        guard isOn(at: now), let bundleId, !alwaysAllowedInFocus.contains(bundleId) else { return false }
        return !allowed.contains { $0.bundleId == bundleId }
    }
}

/// The backdrop gives up on an app focus hid 2 s after the last attempt, or 10 s into a row of them, so an app that
/// won't hide or keeps bringing itself back can't hold it up.
public let focusCoverLimit: TimeInterval = 2
public let focusCoverStreakLimit: TimeInterval = 10
/// And it stays up at least this long after an attempt: it reads as a no instead of a blink, and an app whose windows
/// are still on their way up from the Dock's click isn't taken for gone.
public let focusCoverMinimum: TimeInterval = 0.25

public enum Leaving: Equatable { case gone, leaving, stuck }

/// An app focus hid, followed every 30 ms until it's really gone. Attempts until it's forgotten are the same row.
public struct LeavingApp: Equatable {
    public let first: Date
    public private(set) var last: Date
    /// False for apps focus hid as it started: they leave quietly, the backdrop never covers them.
    public let covers: Bool

    public init(at now: Date, covers: Bool = true) {
        first = now
        last = now
        self.covers = covers
    }

    public mutating func attempted(at now: Date) { last = now }

    /// Past the limits: the backdrop doesn't cover it any more.
    public func isStuck(at now: Date) -> Bool {
        now.timeIntervalSince(last) >= focusCoverLimit || now.timeIntervalSince(first) >= focusCoverStreakLimit
    }

    /// Gone once it's hidden, not in front and has no window on screen, from `focusCoverMinimum` after the last attempt.
    /// Leaving until then: the backdrop stays up and it gets hidden again. Stuck past the limits.
    public func state(active: Bool, hidden: Bool, onScreen: Bool, at now: Date) -> Leaving {
        if hidden, !active, !onScreen, now.timeIntervalSince(last) >= focusCoverMinimum { return .gone }
        return isStuck(at: now) ? .stuck : .leaving
    }

    /// Forgotten once it's been gone `focusCoverLimit` after the last attempt, so an app that keeps bringing itself back
    /// stays one row and hits the streak limit. A stuck one is kept while it's up, so it isn't a new attempt every time.
    public func isOver(active: Bool, hidden: Bool, onScreen: Bool, at now: Date) -> Bool {
        state(active: active, hidden: hidden, onScreen: onScreen, at: now) == .gone && now.timeIntervalSince(last) >= focusCoverLimit
    }
}

/// The once-a-second check under the notifications: an app outside focus that's in front, or not hidden with a window
/// on screen, got past them. Clicking one in the Dock over and over sometimes did.
public func slippedPastFocus(active: Bool, hidden: Bool, onScreen: Bool) -> Bool {
    active || (!hidden && onScreen)
}

/// "25 min", "2 h", "1 h 30 min".
public func durationText(_ minutes: Int) -> String {
    switch (minutes / 60, minutes % 60) {
    case (0, let m): "\(m) min"
    case (let h, 0): "\(h) h"
    case (let h, let m): "\(h) h \(m) min"
    }
}

/// "1:42" style hours and minutes for the menu bar. Rounds up so it never shows 0:00 while time is left.
public func minuteCountdown(_ seconds: TimeInterval) -> String {
    let m = Int((seconds / 60).rounded(.up))
    return "\(m / 60):" + String(format: "%02d", m % 60)
}
