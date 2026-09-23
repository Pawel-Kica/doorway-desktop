import Foundation

/// Apps a focus session never hides: Finder and Simple Block itself.
public let alwaysAllowedInFocus: Set<String> = ["com.apple.finder", "com.pawel.simple-block"]

/// Allowlists have the blocklists' shape: a named list of apps, e.g. "Deep work". Focus uses the ones picked for it.
public typealias Allowlist = Blocklist

/// Everything that decides what focus allows: the allowlists, the ones picked for focus, and apps allowed on their own.
/// `allowed` is worked out on every call, so editing a list or the picks during a focus applies right away.
public struct FocusRules: Equatable {
    public var allowlists: [Allowlist]
    /// Allowlists focus uses, picked in the Focus tab. IDs of deleted lists are ignored.
    public var picked: Set<UUID>
    /// Apps allowed outside any list ("Also allow" in the Focus tab).
    public var apps: [GatedApp]

    public init(allowlists: [Allowlist] = [], picked: Set<UUID> = [], apps: [GatedApp] = []) {
        self.allowlists = allowlists
        self.picked = picked
        self.apps = apps
    }

    /// Focus before allowlists had only its own apps. They become a picked allowlist "Deep work"
    /// and the own apps start empty. No apps, no list.
    public static func migrated(apps: [GatedApp]) -> FocusRules {
        guard !apps.isEmpty else { return FocusRules() }
        let list = Allowlist(name: "Deep work", entries: apps)
        return FocusRules(allowlists: [list], picked: [list.id])
    }

    /// Picked allowlists in Settings order.
    public var pickedLists: [Allowlist] { allowlists.filter { picked.contains($0.id) } }

    /// The picked allowlists' apps, unique by bundle ID.
    public var listed: [GatedApp] { unique(pickedLists.flatMap(\.entries)) }

    /// What focus allows: the picked allowlists' apps, then the apps on their own, unique by bundle ID.
    public var allowed: [GatedApp] { unique(listed + apps) }

    /// For toasts, the popover and the log, e.g. "Deep work, Slack": picked lists that hold apps, then own apps
    /// that aren't in one of them.
    public var names: String {
        let lists = pickedLists.filter { !$0.entries.isEmpty }
        let inLists = Set(lists.flatMap(\.entries).map(\.bundleId))
        return (lists.map(\.name) + apps.filter { !inLists.contains($0.bundleId) }.map(\.name)).joined(separator: ", ")
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
