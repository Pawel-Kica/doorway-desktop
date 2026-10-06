import Foundation

/// Per-app unlock timers keyed by bundle ID. Each one runs a fixed length from the moment a reason is submitted.
public struct AppTimers {
    public private(set) var ends: [String: Date] = [:]

    public init() {}

    public mutating func start(_ bundleId: String, minutes: Int, now: Date) {
        ends[bundleId] = now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    public func remaining(_ bundleId: String, now: Date) -> TimeInterval {
        max(0, ends[bundleId]?.timeIntervalSince(now) ?? 0)
    }

    public func isRunning(_ bundleId: String, now: Date) -> Bool {
        remaining(bundleId, now: now) > 0
    }

    /// Ends a timer early, e.g. when a super lock starts.
    public mutating func stop(_ bundleId: String) {
        ends[bundleId] = nil
    }

    /// Removes the timers that ended at or before `now` and returns their bundle IDs.
    public mutating func popExpired(now: Date) -> [String] {
        let done = ends.filter { $0.value <= now }.map(\.key)
        for id in done { ends[id] = nil }
        return done
    }
}

/// "3:12" style countdown, "2:41:00" from an hour up. Rounds up so it never shows 0:00 while time is left.
public func countdown(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.up))
    if s >= 3600 { return "\(s / 3600):" + String(format: "%02d:%02d", s / 60 % 60, s % 60) }
    return "\(s / 60):" + String(format: "%02d", s % 60)
}
