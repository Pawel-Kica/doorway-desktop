import AppKit
import SimpleBlockCore
import UniformTypeIdentifiers

/// App state for the menu bar and Settings: the rules (blocklists and sessions), time per reason, focus, the log,
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
    /// Apps a focus session allows. They prefill the next focus, and edits during one apply right away.
    @Published var focusApps: [GatedApp] {
        didSet { save(focusApps, "focusApps") }
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

    private let log = ReasonLog(url: ReasonLog.defaultURL)

    private init() {
        let defaults = UserDefaults.standard
        minutesPerReason = defaults.object(forKey: "minutesPerReason") as? Int ?? 5
        entries = log.readAll()
        focusApps = Self.load("focusApps") ?? []
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
        if let session: FocusSession = Self.load("focusSession") {
            if session.isOn(at: now) {
                focus = session
            } else {
                // It ran out while Simple Block wasn't running.
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
        let picked = pickApps()
        guard let index = rules.blocklists.firstIndex(where: { $0.id == list }) else { return }
        for app in picked where !rules.blocklists[index].entries.contains(where: { $0.bundleId == app.bundleId }) {
            rules.blocklists[index].entries.append(app)
        }
    }

    /// Focus app names for the menu, toasts and the log: "Obsidian, Todoist".
    var focusNames: String { focusApps.map(\.name).joined(separator: ", ") }

    /// Time left on the running focus, 0 when off. Moves with the clock.
    var focusLeft: TimeInterval { focus?.remaining(at: now) ?? 0 }

    /// Starts a focus session on the focus apps. Gatekeeper hides everything else. Does nothing without focus apps.
    func startFocus(minutes: Int) {
        guard !focusApps.isEmpty else { return }
        let now = Date()
        focus = FocusSession(started: now, ends: now.addingTimeInterval(TimeInterval(minutes * 60)))
    }

    /// Ends focus, early or on time, and logs it. The apps it hid stay hidden.
    func endFocus() {
        guard let focus else { return }
        record(focusEntry(focus, now: Date()))
        self.focus = nil
    }

    /// The `focus` log entry: allowed apps as the reason, minutes it ran, stamped when it ended.
    private func focusEntry(_ session: FocusSession, now: Date) -> LogEntry {
        LogEntry(ts: min(now, session.ends), bundleId: "focus", app: "Focus", kind: .focus,
                 reason: focusNames, minutes: session.minutesRun(at: now))
    }

    /// Adds apps picked in /Applications to the focus apps.
    func addFocusApps() {
        for app in pickApps() { addFocusApp(app) }
    }

    func addFocusApp(_ app: GatedApp) {
        if !focusApps.contains(where: { $0.bundleId == app.bundleId }) { focusApps.append(app) }
    }

    /// Removing the last app during a focus would hide everything but Finder, so it stays until focus ends.
    var canRemoveFocusApp: Bool { focusLeft == 0 || focusApps.count > 1 }

    func removeFocusApp(_ bundleId: String) {
        guard canRemoveFocusApp else { return }
        focusApps.removeAll { $0.bundleId == bundleId }
    }

    /// Apps picked in an open panel on /Applications.
    private func pickApps() -> [GatedApp] {
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
