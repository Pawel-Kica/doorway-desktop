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
    public var blocklists: Set<UUID>
    public var schedule: Schedule
    public var enabled: Bool
    public var superLock: Bool

    public init(id: UUID = UUID(), blocklists: Set<UUID>, schedule: Schedule, enabled: Bool = true, superLock: Bool = false) {
        self.id = id
        self.blocklists = blocklists
        self.schedule = schedule
        self.enabled = enabled
        self.superLock = superLock
    }

    /// Sessions saved before super lock have no `superLock` key.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        blocklists = try c.decode(Set<UUID>.self, forKey: .blocklists)
        schedule = try c.decode(Schedule.self, forKey: .schedule)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        superLock = try c.decodeIfPresent(Bool.self, forKey: .superLock) ?? false
    }
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

/// Entries of every blocklist, unique by bundle ID (the first one wins).
/// For matching running apps and log entries, not for deciding what's gated now.
public func everyEntry(in blocklists: [Blocklist]) -> [GatedApp] {
    unique(blocklists.flatMap(\.entries))
}

/// Enabled scheduled sessions on at `now`.
public func activeSessions(_ sessions: [ScheduledSession], now: Date, calendar: Calendar = .current) -> [ScheduledSession] {
    sessions.filter { $0.enabled && $0.schedule.isActive(at: now, calendar: calendar) }
}

/// Entries gated right now: everything in the blocklists of active scheduled sessions and running quick sessions,
/// unique by bundle ID.
public func gatedNow(_ blocklists: [Blocklist], sessions: [ScheduledSession], quickSessions: [QuickSession],
                     now: Date, calendar: Calendar = .current) -> [GatedApp] {
    let ids = activeSessions(sessions, now: now, calendar: calendar).map(\.blocklists)
        + quickSessions.filter { $0.ends > now }.map(\.blocklists)
    let on = ids.reduce(into: Set<UUID>()) { $0.formUnion($1) }
    return unique(blocklists.filter { on.contains($0.id) }.flatMap(\.entries))
}

/// Super-locked sessions on at `now`. They're frozen: Settings can't disable, change or delete them,
/// and their blocklists can't lose entries or be deleted.
public func superLockedSessions(_ sessions: [ScheduledSession], now: Date, calendar: Calendar = .current) -> [ScheduledSession] {
    activeSessions(sessions, now: now, calendar: calendar).filter(\.superLock)
}

/// Entries super-locked right now, unique by bundle ID. Always a subset of `gatedNow`.
public func superLockedNow(_ blocklists: [Blocklist], sessions: [ScheduledSession],
                           now: Date, calendar: Calendar = .current) -> [GatedApp] {
    let on = superLockedSessions(sessions, now: now, calendar: calendar).reduce(into: Set<UUID>()) { $0.formUnion($1.blocklists) }
    return unique(blocklists.filter { on.contains($0.id) }.flatMap(\.entries))
}

/// Blocklists a super-locked session uses right now.
public func frozenBlocklists(_ sessions: [ScheduledSession], now: Date, calendar: Calendar = .current) -> Set<UUID> {
    superLockedSessions(sessions, now: now, calendar: calendar).reduce(into: Set<UUID>()) { $0.formUnion($1.blocklists) }
}

/// When the super lock on `bundleId` ends: the latest end among the super-locked sessions gating it.
/// Nil when one of them never ends (every day, all day). Only meaningful when the app is in `superLockedNow`.
public func superLockEnd(_ bundleId: String, blocklists: [Blocklist], sessions: [ScheduledSession],
                         now: Date, calendar: Calendar = .current) -> Date? {
    let lists = Set(blocklists.filter { $0.entries.contains { $0.bundleId == bundleId } }.map(\.id))
    let ends = superLockedSessions(sessions, now: now, calendar: calendar)
        .filter { !$0.blocklists.isDisjoint(with: lists) }
        .map { $0.schedule.end(of: now, calendar: calendar) }
    if ends.contains(where: { $0 == nil }) { return nil }
    return ends.compactMap { $0 }.max()
}

/// Deletes a blocklist and takes it out of every session. Quick sessions left with no blocklist end.
public func deleteBlocklist(_ id: UUID, blocklists: inout [Blocklist], sessions: inout [ScheduledSession],
                            quickSessions: inout [QuickSession]) {
    blocklists.removeAll { $0.id == id }
    for i in sessions.indices { sessions[i].blocklists.remove(id) }
    for i in quickSessions.indices { quickSessions[i].blocklists.remove(id) }
    quickSessions.removeAll { $0.blocklists.isEmpty }
}

/// Settings from before blocklists (one global schedule over `gatedApps`), or a fresh install:
/// one "Distractions" blocklist and one enabled session with the old schedule. Missing days mean every day.
public func migratedSettings(gatedApps: [GatedApp], scheduleDays: [Int]?, from: Int, to: Int)
    -> (blocklists: [Blocklist], sessions: [ScheduledSession]) {
    let list = Blocklist(name: "Distractions", entries: gatedApps)
    let schedule = Schedule(days: Set(scheduleDays ?? Array(1...7)), from: from, to: to)
    return ([list], [ScheduledSession(blocklists: [list.id], schedule: schedule)])
}

private func unique(_ entries: [GatedApp]) -> [GatedApp] {
    var seen = Set<String>()
    return entries.filter { seen.insert($0.bundleId).inserted }
}
