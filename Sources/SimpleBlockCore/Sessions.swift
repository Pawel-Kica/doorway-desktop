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
public struct ScheduledSession: Codable, Identifiable, Equatable {
    public var id: UUID
    public var blocklists: Set<UUID>
    public var schedule: Schedule
    public var enabled: Bool

    public init(id: UUID = UUID(), blocklists: Set<UUID>, schedule: Schedule, enabled: Bool = true) {
        self.id = id
        self.blocklists = blocklists
        self.schedule = schedule
        self.enabled = enabled
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
