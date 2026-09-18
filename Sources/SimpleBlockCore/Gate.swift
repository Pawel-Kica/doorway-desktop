import Foundation

/// Words needed before a reason is accepted. Hardcoded on purpose.
public let minimumWords = 10

/// Words = whitespace-separated tokens, nothing else.
public func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}

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

    /// Removes the timers that ended at or before `now` and returns their bundle IDs.
    public mutating func popExpired(now: Date) -> [String] {
        let done = ends.filter { $0.value <= now }.map(\.key)
        for id in done { ends[id] = nil }
        return done
    }

    /// The running timer that ends first, for the menu bar countdown.
    public func soonest(now: Date) -> (bundleId: String, remaining: TimeInterval)? {
        guard let first = ends.filter({ $0.value > now }).min(by: { $0.value < $1.value }) else { return nil }
        return (first.key, first.value.timeIntervalSince(now))
    }
}

/// "3:12" style countdown, "2:41:00" from an hour up. Rounds up so it never shows 0:00 while time is left.
public func countdown(_ seconds: TimeInterval) -> String {
    let s = Int(seconds.rounded(.up))
    if s >= 3600 { return "\(s / 3600):" + String(format: "%02d:%02d", s / 60 % 60, s % 60) }
    return "\(s / 60):" + String(format: "%02d", s % 60)
}

/// 1st, 2nd, 3rd, 4th, 11th, 21st...
public func ordinal(_ n: Int) -> String {
    let suffix: String
    switch (n % 10, n % 100) {
    case (_, 11...13): suffix = "th"
    case (1, _): suffix = "st"
    case (2, _): suffix = "nd"
    case (3, _): suffix = "rd"
    default: suffix = "th"
    }
    return "\(n)\(suffix)"
}
