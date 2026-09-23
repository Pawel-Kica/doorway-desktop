import Foundation

/// Apps a focus session never hides: Finder and Simple Block itself.
public let alwaysAllowedInFocus: Set<String> = ["com.apple.finder", "com.pawel.simple-block"]

/// A running focus session: until `ends` only its allowed apps may come to the front, everything else gets hidden.
/// The allowed apps aren't stored here, they're the model's focus apps, so editing them applies right away.
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
