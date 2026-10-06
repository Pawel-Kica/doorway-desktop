import AppKit
import DoorwayDesktopCore
import UniformTypeIdentifiers

/// App state for Settings: the rules (blocklists and sessions), focus and its
/// allowlists, the log, the unlock timers and a clock that Gatekeeper ticks every second. Gatekeeper does the gating with it.
/// Settings live in UserDefaults, the log in reasons.jsonl.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var rules: Rules {
        didSet {
            save(rules.blocklists, "blocklists")
            save(rules.sessions, "sessions")
            save(rules.quickSessions, "quickSessions")
        }
    }
    /// What focus allows: allowlists and the ones picked for focus. Edits during a focus apply right away.
    @Published var focusRules: FocusRules {
        didSet { saveFocusRules() }
    }
    /// The running focus session, nil when off. Kept across relaunches.
    @Published var focus: FocusSession? = nil {
        didSet {
            if let focus { save(focus, "focusSession") } else { UserDefaults.standard.removeObject(forKey: "focusSession") }
        }
    }
    @Published var settingsTab = SettingsTab.sessions
    @Published private(set) var entries: [LogEntry]
    /// Per-app unlock timers, started and stopped by Gatekeeper.
    @Published var timers = AppTimers()
    @Published private(set) var now = Date()
    /// Whether Dock clicks on apps focus keeps out get stopped: Accessibility is granted. Set by Gatekeeper.
    @Published var dockGuarded = false

    private let log = ReasonLog(url: ReasonLog.defaultURL)

    private init() {
        let defaults = UserDefaults.standard
        entries = log.readAll()
        let allowlists: [Allowlist]? = Self.load("allowlists")
        // Before allowlists focus had only its own apps (`focusApps`, read only here): they become the list "Deep work".
        focusRules = allowlists.map { FocusRules(allowlists: $0, picked: Self.load("focusAllowlists") ?? []) }
            ?? .migrated(apps: Self.load("focusApps") ?? [])
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
        // Saved even with nothing to move, so the migration runs once.
        if allowlists == nil { saveFocusRules() }
        if let session: FocusSession = Self.load("focusSession") {
            if session.isOn(at: now) {
                focus = session
            } else {
                // It ran out while Doorway Desktop wasn't running.
                record(focusEntry(session, now: now))
                defaults.removeObject(forKey: "focusSession")
            }
        }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Writes a setting as JSON data.
    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func saveFocusRules() {
        save(focusRules.allowlists, "allowlists")
        save(focusRules.picked, "focusAllowlists")
    }

    /// Moves the clock on and ends quick sessions that ran out. Gatekeeper calls it every second.
    func tick() -> Date {
        now = Date()
        if rules.quickSessions.contains(where: { $0.ends <= now }) { rules.quickSessions.removeAll { $0.ends <= now } }
        return now
    }

    /// Appends to reasons.jsonl and to the History list.
    func record(_ entry: LogEntry) {
        do { try log.append(entry) } catch { NSLog("DoorwayDesktop: can't write log: \(error)") }
        entries.append(entry)
    }

    /// "until 10:00" for a super-locked app, "all day, every day" when it never ends, for "Signal is super locked …".
    func lockedUntil(_ bundleId: String, now: Date) -> String {
        guard let end = rules.superLockEnd(bundleId, at: now) else { return "all day, every day" }
        let time = end.formatted(date: .omitted, time: .shortened)
        return end.timeIntervalSince(now) < 24 * 3600 ? "until \(time)" : "until \(end.formatted(.dateTime.weekday(.wide))) \(time)"
    }

    /// A super-locked session that's on now can't be changed or deleted.
    func isFrozen(_ session: ScheduledSession) -> Bool {
        rules.superLockedSessions(at: now).contains { $0.id == session.id }
    }

    /// A blocklist a frozen session uses can't lose entries or be deleted.
    func isFrozen(list: UUID) -> Bool {
        rules.frozenBlocklists(at: now).contains(list)
    }

    /// Starts a quick session on `lists`, from the Sessions tab.
    func startQuickSession(_ lists: Set<UUID>, minutes: Int) {
        rules.quickSessions.append(QuickSession(blocklists: lists, ends: Date().addingTimeInterval(TimeInterval(minutes * 60))))
    }

    func endQuickSession(_ id: UUID) {
        rules.quickSessions.removeAll { $0.id == id }
    }

    /// Time left on the running focus, 0 when off. Moves with the clock.
    var focusLeft: TimeInterval { focus?.remaining(at: now) ?? 0 }

    /// Starts a focus session on what focus allows. Gatekeeper hides everything else. Does nothing when it allows nothing.
    func startFocus(minutes: Int) {
        guard !focusRules.allowed.isEmpty else { return }
        let now = Date()
        focus = FocusSession(started: now, ends: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// Ends focus, early or on time, and logs it. The apps it hid stay hidden.
    func endFocus() {
        guard let focus else { return }
        record(focusEntry(focus, now: Date()))
        self.focus = nil
    }

    /// The `focus` log entry: allowlist and app names as the reason, minutes it ran, stamped when it ended.
    private func focusEntry(_ session: FocusSession, now: Date) -> LogEntry {
        LogEntry(ts: min(now, session.ends), bundleId: "focus", app: "Focus", kind: .focus,
                 reason: focusRules.names, minutes: session.minutesRun(at: now))
    }

    /// A change that would leave a running focus allowing nothing (everything but Finder hidden) waits until it ends.
    func canChangeFocus(_ change: (inout FocusRules) -> Void) -> Bool {
        guard focusLeft > 0 else { return true }
        var changed = focusRules
        change(&changed)
        return !changed.allowed.isEmpty
    }

    /// Apps picked in an open panel on /Applications.
    func pickApps() -> [GatedApp] {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return [] }
        return panel.urls.compactMap { url in
            Bundle(url: url)?.bundleIdentifier.map { GatedApp(bundleId: $0, name: url.deletingPathExtension().lastPathComponent, path: url.path) }
        }
    }

    /// Logs `quit`. Quitting is the off switch. The app delegate calls it on the way out: ⌘Q or the Dock.
    func recordQuit() {
        record(LogEntry(ts: Date(), bundleId: Bundle.main.bundleIdentifier ?? "com.pawel.doorway-desktop", app: "Doorway Desktop", kind: .quit))
    }

    private static func signalIfInstalled() -> [GatedApp] {
        let id = "org.whispersystems.signal-desktop"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return [] }
        return [GatedApp(bundleId: id, name: "Signal", path: url.path)]
    }
}
