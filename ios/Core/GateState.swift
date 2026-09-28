import Foundation

/// The four rules, all editable on the Home screen.
public struct Settings: Codable, Equatable, Sendable {
    /// Opens per day that only need a short reason. 0 means every reason is a long one.
    public var shortPerDay = 5
    public var shortWords = 5
    public var longWords = 30
    /// How long a gated app stays open after a reason.
    public var unlockMinutes = 5

    public init() {}
}

/// One answer to the prompt. Resisted ("Never mind") entries have no reason and opened == false.
public struct Entry: Codable, Equatable, Sendable {
    public var date: Date
    public var app: GatedApp
    public var reason: String?
    public var opened: Bool

    public init(date: Date, app: GatedApp, reason: String?, opened: Bool) {
        self.date = date
        self.app = app
        self.reason = reason
        self.opened = opened
    }
}

/// Everything the app stores, persisted as one JSON blob. Pass `now` and `calendar` in so tests control time.
public struct GateState: Codable, Equatable, Sendable {
    public var settings = Settings()
    /// Oldest first, trimmed to the last 30 days.
    public var entries: [Entry] = []
    public var unlockedUntil: [GatedApp: Date] = [:]

    public init() {}

    /// Entries from the same local calendar day as `now`, oldest first.
    public func entriesToday(now: Date, calendar: Calendar = .current) -> [Entry] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Gated apps opened with a reason today. Resisted entries don't count.
    public func opensToday(now: Date, calendar: Calendar = .current) -> Int {
        entriesToday(now: now, calendar: calendar).filter(\.opened).count
    }

    public func resistedToday(now: Date, calendar: Calendar = .current) -> Int {
        entriesToday(now: now, calendar: calendar).filter { !$0.opened }.count
    }

    public func shortLeft(now: Date, calendar: Calendar = .current) -> Int {
        max(0, settings.shortPerDay - opensToday(now: now, calendar: calendar))
    }

    /// Words the next reason needs: short while today's short ones last, long after.
    public func requiredWords(now: Date, calendar: Calendar = .current) -> Int {
        shortLeft(now: now, calendar: calendar) > 0 ? settings.shortWords : settings.longWords
    }

    /// True while a reason given in the last `unlockMinutes` still covers the app.
    public func isUnlocked(_ app: GatedApp, now: Date) -> Bool {
        guard let until = unlockedUntil[app] else { return false }
        return now < until
    }

    /// Logs an opened entry and unlocks the app for `unlockMinutes`.
    public mutating func open(_ app: GatedApp, reason: String, now: Date, calendar: Calendar = .current) {
        entries.append(Entry(date: now, app: app, reason: reason, opened: true))
        unlockedUntil[app] = now.addingTimeInterval(TimeInterval(settings.unlockMinutes * 60))
        trim(now: now, calendar: calendar)
    }

    /// Logs a "Never mind".
    public mutating func resist(_ app: GatedApp, now: Date, calendar: Calendar = .current) {
        entries.append(Entry(date: now, app: app, reason: nil, opened: false))
        trim(now: now, calendar: calendar)
    }

    private mutating func trim(now: Date, calendar: Calendar) {
        guard let cutoff = calendar.date(byAdding: .day, value: -30, to: now) else { return }
        entries.removeAll { $0.date < cutoff }
    }
}

/// Words = whitespace-separated tokens, same rule as the Mac app.
public func wordCount(_ text: String) -> Int {
    text.split(whereSeparator: { $0.isWhitespace }).count
}
