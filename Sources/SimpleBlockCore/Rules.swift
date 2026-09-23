import Foundation

/// A named list of apps, e.g. "Messengers". Sessions point at blocklists, never at entries.
public struct Blocklist: Codable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var entries: [GatedApp]

    public init(id: UUID = UUID(), name: String, entries: [GatedApp] = []) {
        self.id = id
        self.name = name
        self.entries = entries
    }
}

/// A recurring session, e.g. Mon-Fri 8:00-19:00 on "Messengers".
/// With `superLock` its apps never open while it's on: no reason prompt, and the session is frozen in Settings.
public struct ScheduledSession: Codable, Identifiable, Equatable {
    public var id: UUID
    /// Typed by Paweł, e.g. "Deep work mornings". Empty means the session is titled by its blocklists.
    public var name: String
    public var blocklists: Set<UUID>
    public var schedule: Schedule
    public var enabled: Bool
    public var superLock: Bool

    public init(id: UUID = UUID(), name: String = "", blocklists: Set<UUID>, schedule: Schedule, enabled: Bool = true,
                superLock: Bool = false) {
        self.id = id
        self.name = name
        self.blocklists = blocklists
        self.schedule = schedule
        self.enabled = enabled
        self.superLock = superLock
    }

    /// Sessions saved before super lock have no `superLock` key, before names no `name`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        blocklists = try c.decode(Set<UUID>.self, forKey: .blocklists)
        schedule = try c.decode(Schedule.self, forKey: .schedule)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        superLock = try c.decodeIfPresent(Bool.self, forKey: .superLock) ?? false
    }

    /// What the session does at `now`, for its row in Settings.
    public func status(at now: Date, calendar: Calendar = .current) -> SessionStatus {
        guard enabled else { return .off }
        if schedule.isActive(at: now, calendar: calendar) {
            return schedule.end(of: now, calendar: calendar).map { .on(until: $0) } ?? .alwaysOn
        }
        return schedule.nextStart(after: now, calendar: calendar).map { .starts($0) } ?? .off
    }
}

/// A scheduled session's state at a moment.
public enum SessionStatus: Equatable {
    /// On now, ends at `until`.
    case on(until: Date)
    /// Every day, all day: never ends.
    case alwaysOn
    /// Enabled but off now, starts next at the date.
    case starts(Date)
    /// Disabled, or no day picked.
    case off
}

/// A session started from the menu bar that runs until `ends`.
public struct QuickSession: Codable, Identifiable, Equatable {
    public var id: UUID
    public var blocklists: Set<UUID>
    public var ends: Date

    public init(id: UUID = UUID(), blocklists: Set<UUID>, ends: Date) {
        self.id = id
        self.blocklists = blocklists
        self.ends = ends
    }
}

/// What a blocklisted app gets when it launches, activates or unhides.
public enum Access: Equatable {
    /// Opens freely: no session gates it now, or its timer runs.
    case open
    /// Hidden until a reason is given.
    case ask
    /// Super lock: quit, no prompt.
    case lock
}

/// Everything that decides what's gated when: the blocklists and the sessions pointing at them.
public struct Rules: Equatable {
    public var blocklists: [Blocklist]
    public var sessions: [ScheduledSession]
    public var quickSessions: [QuickSession]

    public init(blocklists: [Blocklist] = [], sessions: [ScheduledSession] = [], quickSessions: [QuickSession] = []) {
        self.blocklists = blocklists
        self.sessions = sessions
        self.quickSessions = quickSessions
    }

    /// Settings from before blocklists (one global schedule over `gatedApps`), or a fresh install:
    /// one "Distractions" blocklist and one enabled session with the old schedule. Missing days mean every day.
    public static func migrated(gatedApps: [GatedApp], scheduleDays: [Int]?, from: Int, to: Int) -> Rules {
        let list = Blocklist(name: "Distractions", entries: gatedApps)
        let schedule = Schedule(days: Set(scheduleDays ?? Array(1...7)), from: from, to: to)
        return Rules(blocklists: [list], sessions: [ScheduledSession(blocklists: [list.id], schedule: schedule)])
    }

    /// Entries of every blocklist, unique by bundle ID (the first one wins).
    /// For matching running apps and log entries, not for deciding what's gated now.
    public var everyEntry: [GatedApp] { unique(blocklists.flatMap(\.entries)) }

    /// The blocklist entry for a running app, if it's in any blocklist.
    public func entry(_ bundleId: String?) -> GatedApp? {
        blocklists.lazy.flatMap(\.entries).first { $0.bundleId == bundleId }
    }

    /// Blocklist names for a session, in Settings order.
    public func names(_ lists: Set<UUID>) -> String {
        let names = blocklists.filter { lists.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No blocklist" : names.joined(separator: ", ")
    }

    /// A session's title in Settings: its name, or its blocklists when it has none.
    public func title(_ session: ScheduledSession) -> String {
        let typed = session.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.isEmpty ? names(session.blocklists) : typed
    }

    /// Enabled scheduled sessions on at `now`.
    public func activeSessions(at now: Date, calendar: Calendar = .current) -> [ScheduledSession] {
        sessions.filter { $0.enabled && $0.schedule.isActive(at: now, calendar: calendar) }
    }

    /// Entries gated right now: everything in the blocklists of active scheduled sessions and running quick sessions,
    /// unique by bundle ID.
    public func gated(at now: Date, calendar: Calendar = .current) -> [GatedApp] {
        let ids = activeSessions(at: now, calendar: calendar).map(\.blocklists)
            + quickSessions.filter { $0.ends > now }.map(\.blocklists)
        return entries(in: ids.reduce(into: Set<UUID>()) { $0.formUnion($1) })
    }

    /// Super-locked sessions on at `now`. They're frozen: Settings can't disable, change or delete them,
    /// and their blocklists can't lose entries or be deleted.
    public func superLockedSessions(at now: Date, calendar: Calendar = .current) -> [ScheduledSession] {
        activeSessions(at: now, calendar: calendar).filter(\.superLock)
    }

    /// Blocklists a super-locked session uses right now.
    public func frozenBlocklists(at now: Date, calendar: Calendar = .current) -> Set<UUID> {
        superLockedSessions(at: now, calendar: calendar).reduce(into: Set<UUID>()) { $0.formUnion($1.blocklists) }
    }

    /// Entries super-locked right now, unique by bundle ID. Always a subset of `gated(at:)`.
    public func superLocked(at now: Date, calendar: Calendar = .current) -> [GatedApp] {
        entries(in: frozenBlocklists(at: now, calendar: calendar))
    }

    /// When the super lock on `bundleId` ends: the latest end among the super-locked sessions gating it.
    /// Nil when one of them never ends (every day, all day). Only meaningful when the app is in `superLocked(at:)`.
    public func superLockEnd(_ bundleId: String, at now: Date, calendar: Calendar = .current) -> Date? {
        let lists = Set(blocklists.filter { $0.entries.contains { $0.bundleId == bundleId } }.map(\.id))
        let ends = superLockedSessions(at: now, calendar: calendar)
            .filter { !$0.blocklists.isDisjoint(with: lists) }
            .map { $0.schedule.end(of: now, calendar: calendar) }
        if ends.contains(where: { $0 == nil }) { return nil }
        return ends.compactMap { $0 }.max()
    }

    /// The gate itself. Super lock wins over everything, a running timer over the reason prompt.
    public func access(_ bundleId: String, timers: AppTimers, at now: Date, calendar: Calendar = .current) -> Access {
        if superLocked(at: now, calendar: calendar).contains(where: { $0.bundleId == bundleId }) { return .lock }
        let gated = gated(at: now, calendar: calendar).contains { $0.bundleId == bundleId }
        return gated && !timers.isRunning(bundleId, now: now) ? .ask : .open
    }

    /// Deletes a blocklist and takes it out of every session. Quick sessions left with no blocklist end.
    public mutating func deleteBlocklist(_ id: UUID) {
        blocklists.removeAll { $0.id == id }
        for i in sessions.indices { sessions[i].blocklists.remove(id) }
        for i in quickSessions.indices { quickSessions[i].blocklists.remove(id) }
        quickSessions.removeAll { $0.blocklists.isEmpty }
    }

    /// Copies a session right below itself, disabled so it gates nothing until it's edited. Returns the copy's ID.
    @discardableResult
    public mutating func duplicateSession(_ id: UUID) -> UUID? {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = sessions[index]
        copy.id = UUID()
        copy.enabled = false
        sessions.insert(copy, at: index + 1)
        return copy.id
    }

    private func entries(in lists: Set<UUID>) -> [GatedApp] {
        unique(blocklists.filter { lists.contains($0.id) }.flatMap(\.entries))
    }
}

private func unique(_ entries: [GatedApp]) -> [GatedApp] {
    var seen = Set<String>()
    return entries.filter { seen.insert($0.bundleId).inserted }
}
