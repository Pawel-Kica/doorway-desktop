import AppKit
import ServiceManagement
import SimpleBlockCore
import UniformTypeIdentifiers

/// What brought the prompt up.
enum Trigger {
    case launch, `switch`, expired

    var kind: LogKind {
        switch self {
        case .launch: .launch
        case .switch: .switch
        case .expired: .expired
        }
    }

    func question(_ app: String) -> String {
        switch self {
        case .launch: "Why are you opening \(app)?"
        case .switch: "Why are you switching to \(app)?"
        case .expired: "Time's up. Why stay in \(app)?"
        }
    }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case sessions = "Sessions", blocklists = "Blocklists", general = "General", history = "History"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .sessions: "calendar"
        case .blocklists: "list.bullet.rectangle"
        case .general: "gearshape"
        case .history: "clock"
        }
    }
}

/// App state plus the gating logic: watches NSWorkspace, hides gated apps, runs the prompt and the timers.
/// What's gated comes from sessions: scheduled ones and quick ones started from the menu bar, each pointing at blocklists.
/// Settings live in UserDefaults, the log in reasons.jsonl.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var minutesPerReason: Int {
        didSet { UserDefaults.standard.set(minutesPerReason, forKey: "minutesPerReason") }
    }
    @Published var blocklists: [Blocklist] {
        didSet { save(blocklists, "blocklists") }
    }
    @Published var sessions: [ScheduledSession] {
        didSet { save(sessions, "sessions") }
    }
    @Published var quickSessions: [QuickSession] {
        didSet { save(quickSessions, "quickSessions") }
    }
    @Published var settingsTab = SettingsTab.sessions
    @Published private(set) var entries: [LogEntry]
    @Published private(set) var timers = AppTimers()
    @Published private(set) var now = Date()

    private let log = ReasonLog(url: ReasonLog.defaultURL)
    private let prompt = PromptController()

    private init() {
        let defaults = UserDefaults.standard
        minutesPerReason = defaults.object(forKey: "minutesPerReason") as? Int ?? 5
        entries = log.readAll()
        if var lists: [Blocklist] = Self.load("blocklists") {
            // Sites (Chrome tabs and web apps) were dropped; their entries had a URL as the path.
            for i in lists.indices { lists[i].entries.removeAll { $0.path.contains("://") } }
            blocklists = lists
            sessions = Self.load("sessions") ?? []
            quickSessions = Self.load("quickSessions") ?? []
        } else {
            // Before blocklists: one schedule over gatedApps. The old keys stay, they're just not read again.
            (blocklists, sessions) = migratedSettings(
                gatedApps: Self.load("gatedApps") ?? Self.signalIfInstalled(),
                scheduleDays: defaults.array(forKey: "scheduleDays") as? [Int],
                from: defaults.integer(forKey: "scheduleFrom"),
                to: defaults.integer(forKey: "scheduleTo"))
            quickSessions = []
            save(blocklists, "blocklists")
            save(sessions, "sessions")
        }
    }

    private static func load<T: Decodable>(_ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    /// Writes a setting as JSON data.
    private func save<T: Encodable>(_ value: T, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(value), forKey: key)
    }

    /// Entries of every blocklist, for matching running apps to an entry.
    var everyEntry: [GatedApp] { SimpleBlockCore.everyEntry(in: blocklists) }

    /// Entries the running sessions gate at `now`.
    func gated(at now: Date) -> [GatedApp] {
        gatedNow(blocklists, sessions: sessions, quickSessions: quickSessions, now: now)
    }

    private func isGated(_ entry: GatedApp, now: Date) -> Bool {
        gated(at: now).contains { $0.bundleId == entry.bundleId }
    }

    /// Starts a quick session from the menu bar.
    func startQuickSession(_ lists: Set<UUID>, minutes: Int) {
        quickSessions.append(QuickSession(blocklists: lists, ends: Date().addingTimeInterval(TimeInterval(minutes * 60))))
    }

    func endQuickSession(_ id: UUID) {
        quickSessions.removeAll { $0.id == id }
    }

    /// Blocklist names for a session, in Settings order.
    func names(_ lists: Set<UUID>) -> String {
        let names = blocklists.filter { lists.contains($0.id) }.map(\.name)
        return names.isEmpty ? "No blocklist" : names.joined(separator: ", ")
    }

    func deleteBlocklist(_ id: UUID) {
        // Copies, so each didSet reads the other settings without an overlapping access.
        var lists = blocklists, scheduled = sessions, quick = quickSessions
        SimpleBlockCore.deleteBlocklist(id, blocklists: &lists, sessions: &scheduled, quickSessions: &quick)
        sessions = scheduled
        quickSessions = quick
        blocklists = lists
    }

    /// Called once at launch.
    func start() {
        registerLoginItem()
        prompt.prepare()
        let center = NSWorkspace.shared.notificationCenter
        // Unhide matters too: Electron apps like Signal unhide themselves when their window finishes loading.
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.gate(app) }
            }
        }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        gate(NSWorkspace.shared.frontmostApplication)
    }

    private func running(_ gated: GatedApp) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: gated.bundleId)
    }

    /// Hides a gated app and asks for a reason, unless no session gates it now or its timer is running.
    private func gate(_ app: NSRunningApplication?, expired: Bool = false) {
        guard let app else { return }
        let gated = everyEntry.first { $0.bundleId == app.bundleIdentifier }
        // Hiding the gated app hands activation to another app, which takes the keyboard from the prompt. Take it back.
        if prompt.isShowing, gated?.id != prompt.bundleId, app != NSRunningApplication.current {
            prompt.bringToFront()
        }
        guard let gated else { return }
        let now = Date()
        guard isGated(gated, now: now), !timers.isRunning(gated.bundleId, now: now) else { return }
        // Backdrop first, it's instant. hide() waits on the other app and building the prompt takes a moment.
        prompt.cover()
        app.hide()
        if prompt.isShowing {
            prompt.bringToFront()
        } else {
            // Activation often arrives before the launch notification, so a fresh process counts as a launch.
            let launched = app.launchDate.map { now.timeIntervalSince($0) < 10 } ?? false
            ask(gated, trigger: expired ? .expired : launched ? .launch : .switch, now: now)
        }
    }

    private func ask(_ gated: GatedApp, trigger: Trigger, now: Date) {
        prompt.show(
            app: gated, trigger: trigger,
            nthToday: reasonsToday(entries, bundleId: gated.bundleId, now: now) + 1,
            minutes: minutesPerReason,
            onSubmit: { [weak self] reason in self?.submit(gated, trigger: trigger, reason: reason) },
            onCancel: { [weak self] in self?.cancel(gated) })
    }

    private func tick() {
        now = Date()
        if quickSessions.contains(where: { $0.ends <= now }) { quickSessions.removeAll { $0.ends <= now } }
        // Time up: ask again if the app is in front, otherwise quit it (a locked app doesn't stay running).
        for id in timers.popExpired(now: now) {
            guard let gated = everyEntry.first(where: { $0.id == id }) else { continue }
            for app in running(gated) {
                if app.isActive {
                    gate(app, expired: true)
                } else if isGated(gated, now: now) {
                    app.terminate()
                }
            }
        }
        // While the prompt is up its app stays hidden, whatever tries to bring it back.
        if let gated = everyEntry.first(where: { $0.id == prompt.bundleId }) {
            for app in running(gated) where !app.isHidden { app.hide() }
        }
    }

    private func submit(_ app: GatedApp, trigger: Trigger, reason: String) {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(reason) >= minimumWords else { return }
        record(LogEntry(ts: Date(), bundleId: app.bundleId, app: app.name, kind: trigger.kind, reason: reason))
        timers.start(app.bundleId, minutes: minutesPerReason, now: Date())
        prompt.close()
        // Simple Block itself isn't active, so it can't hand activation over. Launch Services can.
        let process = running(app).first
        process?.unhide()
        NSWorkspace.shared.openApplication(at: process?.bundleURL ?? URL(fileURLWithPath: app.path), configuration: .init())
    }

    private func cancel(_ app: GatedApp) {
        record(LogEntry(ts: Date(), bundleId: app.bundleId, app: app.name, kind: .cancelled))
        prompt.close()
        // Quit instead of leaving it hidden: switching to a hidden app flashes its window before we can react,
        // while a fresh launch is covered before it has a window.
        for running in running(app) { running.terminate() }
        // Give focus back to the previous app instead of leaving it on a windowless Simple Block.
        NSApp.hide(nil)
    }

    /// Logs `quit` and exits. Quitting is the off switch.
    func quit() {
        record(LogEntry(ts: Date(), bundleId: Bundle.main.bundleIdentifier ?? "com.pawel.simple-block", app: "Simple Block", kind: .quit))
        NSApp.terminate(nil)
    }

    private func record(_ entry: LogEntry) {
        do { try log.append(entry) } catch { NSLog("SimpleBlock: can't write log: \(error)") }
        entries.append(entry)
    }

    /// Adds apps picked in /Applications to a blocklist.
    func addApps(to list: UUID) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK, let index = blocklists.firstIndex(where: { $0.id == list }) else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !blocklists[index].entries.contains(where: { $0.bundleId == id }) else { continue }
            blocklists[index].entries.append(GatedApp(bundleId: id, name: url.deletingPathExtension().lastPathComponent, path: url.path))
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

    /// Adds itself as a login item while it isn't one. Ad-hoc builds may fail, which is fine.
    private func registerLoginItem() {
        guard SMAppService.mainApp.status == .notRegistered else { return }
        do { try SMAppService.mainApp.register() } catch { NSLog("SimpleBlock: login item registration failed: \(error)") }
    }

    private static func signalIfInstalled() -> [GatedApp] {
        let id = "org.whispersystems.signal-desktop"
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return [] }
        return [GatedApp(bundleId: id, name: "Signal", path: url.path)]
    }
}
