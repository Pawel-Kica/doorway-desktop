import AppKit
import Combine
import SimpleBlockCore

/// The gating: watches apps launch, activate and unhide, hides blocklisted ones and asks for a reason,
/// runs their timers, and quits them on Never mind, time up in the background and super lock.
/// During focus it hides every regular app outside what focus allows, behind the backdrop until it's really gone,
/// and ends focus when time's up.
/// What's gated comes from the model's rules, `Rules.access` decides; `FocusSession.hides` for focus.
@MainActor
final class Gatekeeper {
    private let model: AppModel
    private let backdrop: Backdrop
    private let prompt: PromptController
    private let toast = ToastController()
    private var focusStarts: AnyCancellable?
    /// When each app last got the focus toast and log entry. Launch, activate and unhide fire together for one attempt.
    private var focusNoticed: [String: Date] = [:]
    /// Apps told to quit, by process ID, with when to stop waiting. Signal told to quit while it's still loading
    /// takes ~10 s and unhides itself meanwhile, which used to open a second prompt. Until then it only gets hidden.
    private var quitting: [pid_t: Date] = [:]
    /// Apps focus hid, watched every 30 ms until they're gone and forgotten a moment later (`LeavingApp.isOver`).
    /// The once-a-second sweep only hides a known one again: a stuck one never gets the backdrop or a new log line.
    private var focusLeaving: [NSRunningApplication: LeavingApp] = [:]
    private var focusWatch: Timer?
    /// Stops Dock clicks on apps focus keeps out, once Accessibility is granted.
    private lazy var dockGuard = DockGuard(
        blocks: { [weak self] id in self?.focusStopsDockClick(id) ?? false },
        stopped: { [weak self] id, url in self?.dockClickStopped(id, url: url) })

    init(model: AppModel) {
        self.model = model
        let backdrop = Backdrop()
        self.backdrop = backdrop
        prompt = PromptController(backdrop: backdrop)
    }

    /// Called once at launch.
    func start() {
        backdrop.prepare()
        dockGuard.startIfAllowed()
        dockGuard.armed = model.focus != nil
        let center = NSWorkspace.shared.notificationCenter
        // Unhide matters too: Electron apps like Signal unhide themselves when their window finishes loading.
        let names = [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didActivateApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification]
        for name in names {
            let launched = name == NSWorkspace.didLaunchApplicationNotification
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                MainActor.assumeIsolated { self?.gate(app, launched: launched) }
            }
        }
        let ticker = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(ticker, forMode: .common)
        // A focus restored at launch hides what's outside it too, quietly. Hiding only the app in front handed
        // activation to the next visible app, which then got a toast and a `hidden` line nobody asked for.
        if let focus = model.focus { hideAll(outside: focus) }
        focusStarts = model.$focus.dropFirst().compactMap { $0 }.sink { [weak self] in self?.startFocus($0) }
        gate(NSWorkspace.shared.frontmostApplication)
    }

    private func running(_ entry: GatedApp) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleId)
    }

    /// Activation often arrives before the launch notification, so a process this young counts as a launch.
    private func isFresh(_ app: NSRunningApplication, now: Date) -> Bool {
        app.launchDate.map { now.timeIntervalSince($0) < 10 } ?? false
    }

    /// Super lock quits the app, focus hides apps outside it, the reason gate hides a gated app and asks for a reason.
    /// In that order. Apps being quit only get hidden again. `launched`: from the launch notification alone.
    private func gate(_ app: NSRunningApplication?, expired: Bool = false, launched: Bool = false) {
        guard let app else { return }
        let entry = model.rules.entry(app.bundleIdentifier)
        // Hiding the gated app hands activation to another app, which takes the keyboard from the prompt. Take it back.
        if prompt.isShowing, entry?.bundleId != prompt.bundleId, app != NSRunningApplication.current {
            prompt.bringToFront()
        }
        let now = Date()
        if quitting[app.processIdentifier].map({ $0 > now }) ?? false {
            app.hide()
            if prompt.isShowing { prompt.bringToFront() }
            return
        }
        let access = entry.map { model.rules.access($0.bundleId, timers: model.timers, at: now) } ?? .open
        if let entry, access == .lock {
            lock(app, entry, now: now)
        } else if focusHides(app, now: now) {
            hideForFocus(app, cover: !launched, now: now)
        } else if let entry, access == .ask {
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

    /// Focus only hides apps with the regular activation policy (a Dock icon). Accessory and background ones like
    /// Raycast are left alone, but a menu bar app that's also in the Dock, like Wispr Flow, is regular and gets hidden.
    private func focusHides(_ app: NSRunningApplication, now: Date) -> Bool {
        guard app.activationPolicy == .regular, let focus = model.focus else { return false }
        return focus.hides(app.bundleIdentifier, allowed: model.focusRules.allowed, at: now)
    }

    /// Hides an app outside focus, never quits it. The backdrop goes up first, it's instant, while hiding waits on the
    /// app itself: Chrome stayed readable for up to a second. A launch has no window yet, so it's only covered if one
    /// shows up; an app launched in the background then never blurs the screen. Toast and `hidden` log entry once per attempt.
    private func hideForFocus(_ app: NSRunningApplication, cover: Bool, now: Date) {
        var leaving = focusLeaving[app] ?? LeavingApp(at: now)
        leaving.attempted(at: now)
        focusLeaving[app] = leaving
        if cover, leaving.covers, !leaving.isStuck(at: now) { backdrop.show(for: .focus) }
        app.hide()
        watchFocusLeaving()
        guard let id = app.bundleIdentifier else { return }
        noticeFocusAttempt(id, name: app.localizedName ?? id, icon: app.icon, now: now)
    }

    /// Toast and `hidden` log entry, once per attempt: launch, activate and unhide fire together for one.
    private func noticeFocusAttempt(_ id: String, name: String, icon: NSImage?, now: Date) {
        guard focusNoticed[id].map({ now.timeIntervalSince($0) > 3 }) ?? true else { return }
        focusNoticed[id] = now
        model.record(LogEntry(ts: now, bundleId: id, app: name, kind: .hidden))
        let left = model.focus?.remaining(at: now) ?? 0
        toast.show(icon: icon ?? NSApp.applicationIconImage,
                   title: "\(name) is hidden while you focus", subtitle: "\(model.focusRules.names) · \(countdown(left)) left")
    }

    /// A Dock click gets stopped for an app focus keeps out, unless super lock has it: that one opens and gets quit
    /// with its locked notice, as usual.
    private func focusStopsDockClick(_ id: String) -> Bool {
        let now = Date()
        guard let focus = model.focus, focus.hides(id, allowed: model.focusRules.allowed, at: now) else { return false }
        return model.rules.access(id, timers: model.timers, at: now) != .lock
    }

    private func dockClickStopped(_ id: String, url: URL) {
        let name = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName
            ?? url.deletingPathExtension().lastPathComponent
        noticeFocusAttempt(id, name: name, icon: NSWorkspace.shared.icon(forFile: url.path), now: Date())
    }

    /// Focus starting: close a prompt it makes pointless, hide every running regular app outside it, then open the
    /// first allowed app so it lands in front.
    /// Called before `model.focus` changes, so it gets the new session.
    private func startFocus(_ session: FocusSession) {
        // A reason prompt for an app this focus hides has nothing left to ask. It closes quietly, no `cancelled` line.
        if let id = prompt.bundleId, session.hides(id, allowed: model.focusRules.allowed, at: Date()) { prompt.close() }
        dockGuard.armed = true
        hideAll(outside: session)
        guard let first = model.focusRules.allowed.first else { return }
        // activate() on another app gets refused from the background. Launch Services brings it forward.
        let process = running(first).first
        process?.unhide()
        NSWorkspace.shared.openApplication(at: process?.bundleURL ?? URL(fileURLWithPath: first.path), configuration: .init())
    }

    /// Every 30 ms while apps focus hid are on their way out: hides them again while they're in front or not hidden
    /// (a hide sent while the Dock was activating the app again got lost), covers one that shows up, and lifts the
    /// backdrop once none is left.
    private func watchFocusLeaving() {
        guard focusWatch == nil else { return }
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkFocusLeaving() }
        }
        RunLoop.main.add(timer, forMode: .common)
        focusWatch = timer
    }

    private func checkFocusLeaving() {
        let now = Date()
        let onScreen = appsOnScreen()
        var watching = false
        for (app, leaving) in focusLeaving {
            // Focus ended, the app got allowed or it's being quit meanwhile.
            guard !app.isTerminated, quitting[app.processIdentifier] == nil, focusHides(app, now: now) else {
                focusLeaving[app] = nil
                continue
            }
            let windowUp = onScreen.contains(app.processIdentifier)
            guard leaving.state(active: app.isActive, hidden: app.isHidden, onScreen: windowUp, at: now) == .leaving else {
                continue
            }
            watching = true
            if leaving.covers, app.isActive || windowUp, !backdrop.isHeld(by: .focus) { backdrop.show(for: .focus) }
            if app.isActive || !app.isHidden { app.hide() }
        }
        guard !watching else { return }
        focusWatch?.invalidate()
        focusWatch = nil
        backdrop.release(.focus, fade: true)
    }

    /// Once a second during focus, under the notifications: an app outside focus that got past them is hidden like
    /// any other attempt. A known one only gets hidden again and handed to the watcher. Apps being quit are left to that.
    private func sweepFocus(now: Date) {
        let onScreen = appsOnScreen()
        focusLeaving = focusLeaving.filter { app, leaving in
            !app.isTerminated && !leaving.isOver(active: app.isActive, hidden: app.isHidden,
                                                 onScreen: onScreen.contains(app.processIdentifier), at: now)
        }
        for app in NSWorkspace.shared.runningApplications where quitting[app.processIdentifier] == nil
            && slippedPastFocus(active: app.isActive, hidden: app.isHidden, onScreen: onScreen.contains(app.processIdentifier))
            && focusHides(app, now: now) {
            if focusLeaving[app] == nil {
                hideForFocus(app, cover: true, now: now)
            } else {
                app.hide()
                watchFocusLeaving()
            }
        }
    }

    /// Process IDs with a normal, visible window on screen right now, straight from the window server. Owner and layer
    /// need no Screen Recording permission.
    private func appsOnScreen() -> Set<pid_t> {
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return Set(windows.compactMap { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { return nil }
            return window[kCGWindowOwnerPID as String] as? pid_t
        })
    }

    /// Hides every visible regular app outside focus. Not attempts, so no toast, log entry or backdrop: they're watched
    /// quietly, and the sweep won't take a slow one (Chrome) for an attempt.
    private func hideAll(outside session: FocusSession) {
        let now = Date()
        let allowed = model.focusRules.allowed
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && !app.isHidden {
            guard let id = app.bundleIdentifier, session.hides(id, allowed: allowed, at: now) else { continue }
            app.hide()
            focusLeaving[app] = LeavingApp(at: now, covers: false)
            // Hiding one app can activate another for a moment, that's not an attempt either.
            focusNoticed[id] = now
        }
        watchFocusLeaving()
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
            minutes: model.rules.minutesPerReason(entry.bundleId, at: now),
            onSubmit: { [weak self] reason in self?.submit(entry, trigger: trigger, reason: reason) },
            onCancel: { [weak self] in self?.cancel(entry) })
    }

    private func submit(_ entry: GatedApp, trigger: Trigger, reason: String) {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard wordCount(reason) >= minimumWords else { return }
        model.record(LogEntry(ts: Date(), bundleId: entry.bundleId, app: entry.name, kind: trigger.kind, reason: reason))
        model.timers.start(entry.bundleId, minutes: model.rules.minutesPerReason(entry.bundleId, at: Date()), now: Date())
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
        if model.focus != nil { sweepFocus(now: now) } else { focusLeaving.removeAll() }
        dockGuard.startIfAllowed()
        dockGuard.armed = model.focus != nil
        if model.dockGuarded != dockGuard.isRunning { model.dockGuarded = dockGuard.isRunning }
        // Focus time up: log it and say so. The apps it hid stay hidden.
        if let focus = model.focus, !focus.isOn(at: now) {
            model.endFocus()
            toast.show(icon: NSApp.applicationIconImage, title: "Focus done",
                       subtitle: "\(durationText(focus.minutesRun(at: now))) on \(model.focusRules.names)")
        }
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
