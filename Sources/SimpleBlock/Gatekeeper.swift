import AppKit
import SimpleBlockCore

/// The gating: watches apps launch, activate and unhide, hides blocklisted ones and asks for a reason,
/// runs their timers, and quits them on Never mind, time up in the background and super lock.
/// What's gated comes from the model's rules, `Rules.access` decides.
@MainActor
final class Gatekeeper {
    private let model: AppModel
    private let prompt = PromptController()
    /// Apps told to quit, by process ID, with when to stop waiting. Signal told to quit while it's still loading
    /// takes ~10 s and unhides itself meanwhile, which used to open a second prompt. Until then it only gets hidden.
    private var quitting: [pid_t: Date] = [:]

    init(model: AppModel) {
        self.model = model
    }

    /// Called once at launch.
    func start() {
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

    private func running(_ entry: GatedApp) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleId)
    }

    /// Activation often arrives before the launch notification, so a process this young counts as a launch.
    private func isFresh(_ app: NSRunningApplication, now: Date) -> Bool {
        app.launchDate.map { now.timeIntervalSince($0) < 10 } ?? false
    }

    /// Hides a gated app and asks for a reason, or quits it under super lock. Apps being quit only get hidden again.
    private func gate(_ app: NSRunningApplication?, expired: Bool = false) {
        guard let app else { return }
        let entry = model.rules.entry(app.bundleIdentifier)
        // Hiding the gated app hands activation to another app, which takes the keyboard from the prompt. Take it back.
        if prompt.isShowing, entry?.bundleId != prompt.bundleId, app != NSRunningApplication.current {
            prompt.bringToFront()
        }
        guard let entry else { return }
        let now = Date()
        if quitting[app.processIdentifier].map({ $0 > now }) ?? false {
            app.hide()
            if prompt.isShowing { prompt.bringToFront() }
            return
        }
        switch model.rules.access(entry.bundleId, timers: model.timers, at: now) {
        case .open:
            return
        case .lock:
            lock(app, entry, now: now)
        case .ask:
            // Backdrop first, it's instant. hide() waits on the other app and building the prompt takes a moment.
            prompt.cover()
            app.hide()
            if prompt.isShowing {
                prompt.bringToFront()
            } else {
                ask(entry, trigger: expired ? .expired : isFresh(app, now: now) ? .launch : .switch, now: now)
            }
        }
    }

    /// Hides and quits a gated app. A normal quit: forceTerminate() on a loading Signal left it running,
    /// unknown to Launch Services.
    private func quit(_ app: NSRunningApplication, now: Date) {
        app.hide()
        app.terminate()
        quitting[app.processIdentifier] = now.addingTimeInterval(15)
    }

    /// Super lock: quit the app, show the locked notice once per attempt, log `locked`.
    /// Launch, activate and unhide all fire for one attempt; the ones after this find the app quitting.
    private func lock(_ app: NSRunningApplication, _ entry: GatedApp, now: Date) {
        prompt.cover()
        quit(app, now: now)
        model.timers.stop(entry.bundleId)
        if prompt.isShowing {
            prompt.bringToFront()
            return
        }
        model.record(LogEntry(ts: now, bundleId: entry.bundleId, app: entry.name, kind: .locked))
        prompt.showLocked(app: entry, until: model.lockedUntil(entry.bundleId, now: now)) { [weak self] in
            self?.prompt.close()
            NSApp.hide(nil)
        }
    }

    private func ask(_ entry: GatedApp, trigger: Trigger, now: Date) {
        prompt.show(
            app: entry, trigger: trigger,
            nthToday: reasonsToday(model.entries, bundleId: entry.bundleId, now: now) + 1,
            minutes: model.minutesPerReason,
            onSubmit: { [weak self] reason in self?.submit(entry, trigger: trigger, reason: reason) },
            onCancel: { [weak self] in self?.cancel(entry) })
    }

    private func submit(_ entry: GatedApp, trigger: Trigger, reason: String) {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(reason) >= minimumWords else { return }
        model.record(LogEntry(ts: Date(), bundleId: entry.bundleId, app: entry.name, kind: trigger.kind, reason: reason))
        model.timers.start(entry.bundleId, minutes: model.minutesPerReason, now: Date())
        prompt.close()
        // Simple Block itself isn't active, so it can't hand activation over. Launch Services can.
        let process = running(entry).first
        process?.unhide()
        NSWorkspace.shared.openApplication(at: process?.bundleURL ?? URL(fileURLWithPath: entry.path), configuration: .init())
    }

    private func cancel(_ entry: GatedApp) {
        model.record(LogEntry(ts: Date(), bundleId: entry.bundleId, app: entry.name, kind: .cancelled))
        prompt.close()
        // Quit instead of leaving it hidden: switching to a hidden app flashes its window before we can react,
        // while a fresh launch is covered before it has a window.
        let now = Date()
        for app in running(entry) { quit(app, now: now) }
        // Give focus back to the previous app instead of leaving it on a windowless Simple Block.
        NSApp.hide(nil)
    }

    private func tick() {
        let now = model.tick()
        quitting = quitting.filter { $0.value > now }
        // A super lock starting quits its apps right away, timer or not.
        for locked in model.rules.superLocked(at: now) {
            for app in running(locked) where quitting[app.processIdentifier] == nil { quit(app, now: now) }
            if model.timers.isRunning(locked.bundleId, now: now) { model.timers.stop(locked.bundleId) }
        }
        // Time up: ask again if the app is in front, otherwise quit it (a locked app doesn't stay running).
        for id in model.timers.popExpired(now: now) {
            guard let entry = model.rules.entry(id) else { continue }
            for app in running(entry) {
                if app.isActive {
                    gate(app, expired: true)
                } else if model.rules.access(entry.bundleId, timers: model.timers, at: now) != .open {
                    quit(app, now: now)
                }
            }
        }
        // While the prompt is up its app stays hidden, and so do apps on their way out, whatever tries to bring them back.
        let promptApps = model.rules.entry(prompt.bundleId).map(running) ?? []
        let leaving = quitting.keys.compactMap { NSRunningApplication(processIdentifier: $0) }
        for app in promptApps + leaving where !app.isHidden { app.hide() }
    }
}
