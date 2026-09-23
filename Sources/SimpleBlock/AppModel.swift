import AppKit
import SimpleBlockCore
import UniformTypeIdentifiers

/// App state for the menu bar and Settings: the rules (blocklists and sessions), time per reason, the log,
/// the unlock timers and a clock that Gatekeeper ticks every second. Gatekeeper does the gating with it.
/// Settings live in UserDefaults, the log in reasons.jsonl.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var minutesPerReason: Int {
        didSet { UserDefaults.standard.set(minutesPerReason, forKey: "minutesPerReason") }
    }
    @Published var rules: Rules {
        didSet {
            save(rules.blocklists, "blocklists")
            save(rules.sessions, "sessions")
            save(rules.quickSessions, "quickSessions")
        }
    }
    @Published var settingsTab = SettingsTab.sessions
    @Published private(set) var entries: [LogEntry]
    /// Per-app unlock timers, started and stopped by Gatekeeper.
    @Published var timers = AppTimers()
    @Published private(set) var now = Date()

    private let log = ReasonLog(url: ReasonLog.defaultURL)

    private init() {
        let defaults = UserDefaults.standard
        minutesPerReason = defaults.object(forKey: "minutesPerReason") as? Int ?? 5
        entries = log.readAll()
        if var lists: [Blocklist] = Self.load("blocklists") {
            // Sites (Chrome tabs and web apps) were dropped; their entries had a URL as the path.
            for i in lists.indices { lists[i].entries.removeAll { $0.path.contains("://") } }
            rules = Rules(blocklists: lists, sessions: Self.load("sessions") ?? [], quickSessions: Self.load("quickSessions") ?? [])
        } else {
            // Before blocklists: one schedule over gatedApps. The old keys stay, they're just not read again.
            rules = .migrated(
                gatedApps: Self.load("gatedApps") ?? Self.signalIfInstalled(),
                scheduleDays: defaults.array(forKey: "scheduleDays") as? [Int],
                from: defaults.integer(forKey: "scheduleFrom"),
                to: defaults.integer(forKey: "scheduleTo"))
            save(rules.blocklists, "blocklists")
            save(rules.sessions, "sessions")
        }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Writes a setting as JSON data.
    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// Moves the clock on and ends quick sessions that ran out. Gatekeeper calls it every second.
    func tick() -> Date {
        now = Date()
        if rules.quickSessions.contains(where: { $0.ends <= now }) { rules.quickSessions.removeAll { $0.ends <= now } }
        return now
    }

    /// Appends to reasons.jsonl and to the History list.
    func record(_ entry: LogEntry) {
        do { try log.append(entry) } catch { NSLog("SimpleBlock: can't write log: \(error)") }
        entries.append(entry)
    }

    /// "Locked until 10:00" for a super-locked app, "Locked all day, every day" when it never ends.
    func lockedUntil(_ bundleId: String, now: Date) -> String {
        guard let end = rules.superLockEnd(bundleId, at: now) else { return "Locked all day, every day" }
        let time = end.formatted(date: .omitted, time: .shortened)
        return end.timeIntervalSince(now) < 24 * 3600 ? "Locked until \(time)" : "Locked until \(end.formatted(.dateTime.weekday(.wide))) \(time)"
    }

    /// A super-locked session that's on now can't be changed or deleted.
    func isFrozen(_ session: ScheduledSession) -> Bool {
        rules.superLockedSessions(at: now).contains { $0.id == session.id }
    }

    /// A blocklist a frozen session uses can't lose entries or be deleted.
    func isFrozen(list: UUID) -> Bool {
        rules.frozenBlocklists(at: now).contains(list)
    }

    /// Starts a quick session from the menu bar.
    func startQuickSession(_ lists: Set<UUID>, minutes: Int) {
        rules.quickSessions.append(QuickSession(blocklists: lists, ends: Date().addingTimeInterval(TimeInterval(minutes * 60))))
    }

    func endQuickSession(_ id: UUID) {
        rules.quickSessions.removeAll { $0.id == id }
    }

    /// Adds apps picked in /Applications to a blocklist.
    func addApps(to list: UUID) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK, let index = rules.blocklists.firstIndex(where: { $0.id == list }) else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !rules.blocklists[index].entries.contains(where: { $0.bundleId == id }) else { continue }
            rules.blocklists[index].entries.append(GatedApp(bundleId: id, name: url.deletingPathExtension().lastPathComponent, path: url.path))
        }
    }

    func showLogInFinder() {
        if FileManager.default.fileExists(atPath: log.url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([log.url])
        } else {
            let dir = log.url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            NSWorkspace.shared.open(dir)
        }
    }

    /// Logs `quit` and exits. Quitting is the off switch.
    func quit() {
        record(LogEntry(ts: Date(), bundleId: Bundle.main.bundleIdentifier ?? "com.pawel.simple-block", app: "Simple Block", kind: .quit))
        NSApp.terminate(nil)
    }

    private static func signalIfInstalled() -> [GatedApp] {
        let id = "org.whispersystems.signal-desktop"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return [] }
        return [GatedApp(bundleId: id, name: "Signal", path: url.path)]
    }
}
