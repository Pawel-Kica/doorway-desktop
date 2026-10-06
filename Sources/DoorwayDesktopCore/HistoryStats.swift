import Foundation

/// Where an attempt to open a gated app ended up.
public enum Outcome: CaseIterable {
    /// A reason was given and the app opened (launch, switch, expired).
    case opened
    /// Never mind at the prompt: gave up, a win.
    case neverMind
    /// Kept out without asking: super lock (locked) or a focus session (hidden).
    case blocked
}

extension LogKind {
    /// nil for kinds that aren't an attempt (quit, focus).
    public var outcome: Outcome? {
        switch self {
        case .launch, .switch, .expired: .opened
        case .cancelled: .neverMind
        case .locked, .hidden: .blocked
        case .quit, .focus: nil
        }
    }
}

/// Attempts split by outcome.
public struct OutcomeCounts: Equatable {
    public var opened = 0
    public var neverMind = 0
    public var blocked = 0

    public init(opened: Int = 0, neverMind: Int = 0, blocked: Int = 0) {
        self.opened = opened
        self.neverMind = neverMind
        self.blocked = blocked
    }

    public var total: Int { opened + neverMind + blocked }
    /// Attempts that didn't open the app.
    public var resisted: Int { neverMind + blocked }

    public subscript(outcome: Outcome) -> Int {
        switch outcome {
        case .opened: opened
        case .neverMind: neverMind
        case .blocked: blocked
        }
    }

    /// Counts one entry if its kind is an attempt.
    mutating func add(_ kind: LogKind) {
        switch kind.outcome {
        case .opened: opened += 1
        case .neverMind: neverMind += 1
        case .blocked: blocked += 1
        case nil: break
        }
    }

    public static func + (a: OutcomeCounts, b: OutcomeCounts) -> OutcomeCounts {
        OutcomeCounts(opened: a.opened + b.opened, neverMind: a.neverMind + b.neverMind, blocked: a.blocked + b.blocked)
    }
}

/// One calendar day of the log.
public struct DayStats: Equatable {
    /// Start of the day.
    public let day: Date
    public var counts = OutcomeCounts()
    /// Minutes of focus sessions that ended this day.
    public var focusMinutes = 0
}

/// Attempts on one app.
public struct AppStats: Equatable {
    public let bundleId: String
    /// Name from the newest entry.
    public var app: String
    public var counts = OutcomeCounts()
}

/// Today's headline numbers, each with what to compare it to. A baseline is nil when there's no history to compare with.
public struct TodayStats: Equatable {
    public var attempts: Int
    public var attemptsAverage: Double?
    public var opened: Int
    public var openedAverage: Double?
    /// Share of attempts that didn't open the app over the last 7 days, today included. nil without attempts.
    public var resisted: Double?
    /// Same share for the 7 days before that.
    public var resistedBefore: Double?
    public var focusMinutes: Int
    public var focusAverage: Double?
}

/// Numbers for the History dashboard, all pure functions of the log.
public enum HistoryStats {
    /// The last `count` days, oldest first, ending today. Days without entries are included with zeros.
    public static func days(_ entries: [LogEntry], count: Int, now: Date, calendar: Calendar = .current) -> [DayStats] {
        let today = calendar.startOfDay(for: now)
        var days = (0..<count).reversed().map { DayStats(day: calendar.date(byAdding: .day, value: -$0, to: today)!) }
        for entry in entries {
            let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: entry.ts), to: today).day!
            guard (0..<count).contains(back) else { continue }
            let index = count - 1 - back
            days[index].counts.add(entry.kind)
            if entry.kind == .focus { days[index].focusMinutes += entry.minutes ?? 0 }
        }
        return days
    }

    /// Today against the 7 days before it. Averages only use days on or after the first log entry.
    public static func today(_ entries: [LogEntry], now: Date, calendar: Calendar = .current) -> TodayStats {
        let days = days(entries, count: 14, now: now, calendar: calendar)
        let today = days[13]
        let firstDay = entries.map(\.ts).min().map { calendar.startOfDay(for: $0) }
        let before = days[6..<13].filter { firstDay != nil && $0.day >= firstDay! }
        func average(_ value: (DayStats) -> Int) -> Double? {
            before.isEmpty ? nil : Double(before.map(value).reduce(0, +)) / Double(before.count)
        }
        func share(_ days: ArraySlice<DayStats>) -> Double? {
            let counts = days.map(\.counts).reduce(OutcomeCounts(), +)
            return counts.total == 0 ? nil : Double(counts.resisted) / Double(counts.total)
        }
        return TodayStats(
            attempts: today.counts.total, attemptsAverage: average { $0.counts.total },
            opened: today.counts.opened, openedAverage: average { $0.counts.opened },
            resisted: share(days[7...]), resistedBefore: share(days[..<7]),
            focusMinutes: today.focusMinutes, focusAverage: average(\.focusMinutes))
    }

    /// Apps with the most attempts over the last `days` days, most first, at most `limit`.
    public static func topApps(_ entries: [LogEntry], days: Int = 30, limit: Int = 5, now: Date, calendar: Calendar = .current) -> [AppStats] {
        var apps: [String: AppStats] = [:]
        for entry in recent(entries, days: days, now: now, calendar: calendar) where entry.kind.outcome != nil {
            apps[entry.bundleId, default: AppStats(bundleId: entry.bundleId, app: entry.app)].counts.add(entry.kind)
            apps[entry.bundleId]!.app = entry.app
        }
        let sorted = apps.values.sorted { ($0.counts.total, $1.app) > ($1.counts.total, $0.app) }
        return Array(sorted.prefix(limit))
    }

    /// Attempts per hour of the day (index 0 is midnight) over the last `days` days.
    public static func byHour(_ entries: [LogEntry], days: Int = 30, now: Date, calendar: Calendar = .current) -> [OutcomeCounts] {
        var hours = Array(repeating: OutcomeCounts(), count: 24)
        for entry in recent(entries, days: days, now: now, calendar: calendar) {
            hours[calendar.component(.hour, from: entry.ts)].add(entry.kind)
        }
        return hours
    }

    /// Entries from the start of the day `days - 1` days ago through the end of today.
    private static func recent(_ entries: [LogEntry], days: Int, now: Date, calendar: Calendar) -> [LogEntry] {
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: 1 - days, to: today)!
        let to = calendar.date(byAdding: .day, value: 1, to: today)!
        return entries.filter { $0.ts >= from && $0.ts < to }
    }
}
