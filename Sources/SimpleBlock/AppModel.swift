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
    case general = "General", apps = "Apps", history = "History"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .apps: "square.grid.2x2"
        case .history: "clock"
        }
    }
}

/// App state plus the gating logic: watches NSWorkspace, hides gated apps, runs the prompt and the timers.
/// A site is gated through its Chrome web app, which is its own process, so it goes through the same path as an app.
/// Settings live in UserDefaults, the log in reasons.jsonl.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var minutesPerReason: Int {
        didSet { UserDefaults.standard.set(minutesPerReason, forKey: "minutesPerReason") }
    }
    @Published var schedule: Schedule {
        didSet {
            UserDefaults.standard.set(schedule.days.sorted(), forKey: "scheduleDays")
            UserDefaults.standard.set(schedule.from, forKey: "scheduleFrom")
            UserDefaults.standard.set(schedule.to, forKey: "scheduleTo")
        }
    }
    @Published var gatedApps: [GatedApp] {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(gatedApps), forKey: "gatedApps") }
    }
    @Published var settingsTab = SettingsTab.general
    @Published private(set) var entries: [LogEntry]
    @Published private(set) var timers = AppTimers()
    @Published private(set) var now = Date()

    private let log = ReasonLog(url: ReasonLog.defaultURL)
    private let prompt = PromptController()

    private init() {
        let defaults = UserDefaults.standard
        minutesPerReason = defaults.object(forKey: "minutesPerReason") as? Int ?? 5
        schedule = Schedule(
            days: Set(defaults.array(forKey: "scheduleDays") as? [Int] ?? Array(1...7)),
            from: defaults.integer(forKey: "scheduleFrom"),
            to: defaults.integer(forKey: "scheduleTo"))
        if let data = defaults.data(forKey: "gatedApps"), let apps = try? JSONDecoder().decode([GatedApp].self, from: data) {
            gatedApps = apps
        } else {
            gatedApps = Self.signalIfInstalled()
        }
        entries = log.readAll()
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

    /// The gated entry a running app belongs to: an app by bundle ID, or a site by its web app's start URL.
    private func entry(for app: NSRunningApplication) -> GatedApp? {
        if let gated = gatedApps.first(where: { !$0.isSite && $0.bundleId == app.bundleIdentifier }) { return gated }
        guard let url = app.bundleURL.flatMap(Bundle.init(url:))?.object(forInfoDictionaryKey: webAppURLKey) as? String else { return nil }
        return gatedSite(forWebAppURL: url, in: gatedApps)
    }

    /// Running processes of a gated entry. A site can have several web apps, e.g. two Gmail accounts.
    private func running(_ gated: GatedApp) -> [NSRunningApplication] {
        if !gated.isSite { return NSRunningApplication.runningApplications(withBundleIdentifier: gated.bundleId) }
        return NSWorkspace.shared.runningApplications.filter { entry(for: $0) == gated }
    }

    /// Hides a gated app and asks for a reason, unless it's off-schedule or its timer is running.
    private func gate(_ app: NSRunningApplication?, expired: Bool = false) {
        guard let app else { return }
        let gated = entry(for: app)
        // Hiding the gated app hands activation to another app, which takes the keyboard from the prompt. Take it back.
        if prompt.isShowing, gated?.id != prompt.bundleId, app != NSRunningApplication.current {
            prompt.bringToFront()
        }
        guard let gated else { return }
        let now = Date()
        guard schedule.isActive(at: now), !timers.isRunning(gated.bundleId, now: now) else { return }
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
        // Time up: ask again if the app is in front, otherwise quit it (a locked app doesn't stay running).
        for id in timers.popExpired(now: now) {
            guard let gated = gatedApps.first(where: { $0.id == id }) else { continue }
            for app in running(gated) {
                if app.isActive {
                    gate(app, expired: true)
                } else if schedule.isActive(at: now) {
                    app.terminate()
                }
            }
        }
        // While the prompt is up its app stays hidden, whatever tries to bring it back.
        if let gated = gatedApps.first(where: { $0.id == prompt.bundleId }) {
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
        guard let url = process?.bundleURL ?? (app.isSite ? nil : URL(fileURLWithPath: app.path)) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
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

    func addApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let id = Bundle(url: url)?.bundleIdentifier, !gatedApps.contains(where: { $0.bundleId == id }) else { continue }
            gatedApps.append(GatedApp(bundleId: id, name: url.deletingPathExtension().lastPathComponent, path: url.path))
        }
    }

    /// Installed web apps for a site, found where Chrome puts them: ~/Applications/Chrome Apps.localized.
    /// Other Chromium browsers use a sibling "<Browser> Apps.localized" folder, so every folder in ~/Applications is checked.
    func webApps(for site: GatedApp) -> [URL] {
        let fm = FileManager.default
        let home = fm.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        let folders = [home] + ((try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == "localized" }
        return folders.flatMap { (try? fm.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }.filter {
            guard $0.pathExtension == "app", let url = Bundle(url: $0)?.object(forInfoDictionaryKey: webAppURLKey) as? String else { return false }
            return gatedSite(forWebAppURL: url, in: gatedApps) == site
        }
    }

    /// Opens a site in Chrome, where Paweł installs it as an app. Falls back to the default browser.
    func openInChrome(_ site: GatedApp) {
        guard let url = URL(string: site.path) else { return }
        if let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") {
            NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
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
