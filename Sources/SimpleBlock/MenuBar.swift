import SimpleBlockCore
import SwiftUI

/// Menu bar icon, plus "Signal 3:12" while a timer runs (the one ending first), else a scope and "1:42" during focus.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let running = model.timers.soonest(now: model.now),
           let app = model.rules.entry(running.bundleId) {
            Image(systemName: "hand.raised.fill")
            Text("\(app.name) \(countdown(running.remaining))")
        } else if model.focusLeft > 0 {
            Image(systemName: "scope")
            Text(minuteCountdown(model.focusLeft))
        } else {
            Image(systemName: "hand.raised.fill")
        }
    }
}

/// The menu bar popover: what gates now, gated apps with timers, quick sessions, focus, Start session, Start focus,
/// focus sounds, today's count, Settings, Quit. Drawn at the `uiScale` size, like Settings.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @AppStorage(UIScale.key) private var scale = UIScale.standard
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let gated = model.rules.gated(at: model.now)
        let status = status()
        VStack(alignment: .leading, spacing: 4 * scale) {
            HStack {
                Text("Simple Block").scaledFont(17, weight: .semibold)
                Spacer()
                Text(status.text)
                    .scaledFont(13, weight: .semibold)
                    .lineLimit(1)
                    .foregroundStyle(status.on ? .green : .orange)
                    .padding(.horizontal, 10 * scale).padding(.vertical, 3 * scale)
                    .background((status.on ? Color.green : Color.orange).opacity(0.18), in: Capsule())
            }
            .padding(.horizontal, 8 * scale).padding(.bottom, 10 * scale)

            if gated.isEmpty {
                Text("Nothing gated now").foregroundStyle(.secondary).padding(10 * scale)
            }
            // A running timer shows its countdown, a super lock says when it ends, everything else a lock: it asks for a reason.
            let superLocked = model.rules.superLocked(at: model.now).map(\.bundleId)
            ForEach(gated) { app in
                let left = model.timers.remaining(app.bundleId, now: model.now)
                HStack(spacing: 12 * scale) {
                    AppIcon(app: app, size: 30 * scale)
                    Text(app.name)
                    Spacer()
                    if superLocked.contains(app.bundleId) {
                        Text(model.lockedUntil(app.bundleId, now: model.now))
                            .scaledFont(13).foregroundStyle(.red)
                        Image(systemName: "lock.fill").scaledFont(13).foregroundStyle(.red)
                    } else if left > 0 {
                        Text("\(countdown(left)) left").monospacedDigit()
                    } else {
                        Image(systemName: "lock.fill").scaledFont(13).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10 * scale).padding(.vertical, 5 * scale)
            }

            Divider().padding(.vertical, 8 * scale)
            ForEach(model.rules.quickSessions) { quick in
                HStack(spacing: 12 * scale) {
                    PopoverSymbol(symbol: "timer")
                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text(model.rules.names(quick.blocklists)).lineLimit(1)
                        Text("\(countdown(quick.ends.timeIntervalSince(model.now))) left")
                            .scaledFont(13).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.endQuickSession(quick.id) } label: { Text("End").bezelPadding() }
                }
                .padding(.horizontal, 10 * scale).padding(.vertical, 6 * scale)
            }
            if model.focusLeft > 0 {
                HStack(spacing: 12 * scale) {
                    PopoverSymbol(symbol: "scope")
                    VStack(alignment: .leading, spacing: 1 * scale) {
                        Text("Focus")
                        HStack(spacing: 6 * scale) {
                            Text("\(countdown(model.focusLeft)) left").monospacedDigit()
                            ForEach(model.focusApps) { app in AppIcon(app: app, size: 16 * scale).help(app.name) }
                        }
                        .scaledFont(13).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.endFocus() } label: { Text("End").bezelPadding() }
                }
                .padding(.horizontal, 10 * scale).padding(.vertical, 6 * scale)
            }
            if !model.rules.blocklists.isEmpty { StartSessionMenu(model: model) }
            if model.focusLeft == 0 {
                if model.focusApps.isEmpty {
                    PopoverRow(symbol: "scope", title: "Start focus") { open(.focus) }
                } else {
                    StartFocusMenu(model: model)
                }
            }
            HStack(alignment: .top, spacing: 12 * scale) {
                PopoverSymbol(symbol: "headphones")
                FocusSoundsControl(sounds: FocusSounds.shared, scale: scale)
            }
            .padding(.horizontal, 10 * scale).padding(.vertical, 6 * scale)
            PopoverRow(symbol: "list.bullet", title: "Today's reasons",
                       trailing: "\(reasonsToday(model.entries, now: model.now))") { open(.history) }
            PopoverRow(symbol: "gearshape", title: "Settings…") { open(.sessions) }
            PopoverRow(symbol: "power", title: "Quit") { model.quit() }
        }
        .scaledFont(15)
        .controlSize(UIScale.controlSize(scale))
        .padding(14 * scale)
        .frame(width: 360 * scale)
        .background { GeometryReader { FitWindow(size: $0.size) } }
        .environment(\.uiScale, scale)
    }

    /// What gates now: a super lock first, then a scheduled session (they're the main thing), else the quick session ending last.
    private func status() -> (text: String, on: Bool) {
        let active = model.rules.activeSessions(at: model.now)
        if let session = active.first(where: \.superLock) ?? active.first {
            let kind = session.superLock ? "Super lock" : "Session"
            guard let end = session.schedule.end(of: model.now) else { return ("\(kind) on all day", true) }
            return ("\(kind) on until \(end.formatted(date: .omitted, time: .shortened))", true)
        }
        if let quick = model.rules.quickSessions.filter({ $0.ends > model.now }).max(by: { $0.ends < $1.ends }) {
            return ("Quick session, \(countdown(quick.ends.timeIntervalSince(model.now))) left", true)
        }
        return ("No session now", false)
    }

    /// Opens Settings, on `tab` when given.
    private func open(_ tab: SettingsTab?) {
        if let tab { model.settingsTab = tab }
        dismiss()
        openSettings()
        NSApp.activate()
    }
}

/// Keeps the popover window the size of its content, top edge in place. MenuBarExtra grows its window but never
/// shrinks it, so after a smaller UI scale the popover floated in the middle of a much bigger empty window.
private struct FitWindow: NSViewRepresentable {
    let size: CGSize

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let content = window.contentRect(forFrameRect: window.frame)
            guard abs(content.width - size.width) > 0.5 || abs(content.height - size.height) > 0.5 else { return }
            let fitted = NSRect(x: content.minX, y: content.maxY - size.height, width: size.width, height: size.height)
            window.setFrame(window.frameRect(forContentRect: fitted), display: true)
        }
    }
}

/// "Start session": a submenu per blocklist, plus All blocklists when there's more than one, each with a few lengths.
/// Button menu style with a plain button keeps the row's own label; the borderless style reduces it to icon and text.
private struct StartSessionMenu: View {
    @ObservedObject var model: AppModel
    @State private var hovering = false
    private let lengths = [(30, "30 min"), (60, "1 h"), (120, "2 h"), (180, "3 h"), (240, "4 h")]

    var body: some View {
        Menu {
            if model.rules.blocklists.count > 1 {
                lengthMenu("All blocklists", Set(model.rules.blocklists.map(\.id)))
                Divider()
            }
            ForEach(model.rules.blocklists) { list in lengthMenu(list.name, [list.id]) }
        } label: {
            PopoverRowLabel(symbol: "play.fill", title: "Start session", trailing: nil, hovering: hovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
    }

    private func lengthMenu(_ title: String, _ lists: Set<UUID>) -> some View {
        Menu(title) {
            ForEach(lengths, id: \.0) { minutes, label in
                Button(label) { model.startQuickSession(lists, minutes: minutes) }
            }
        }
    }
}

/// "Start focus": a few lengths under the focus apps' names. Picking one closes the popover, which would
/// otherwise stay open over the first focus app (Simple Block isn't active, so it doesn't close by itself).
private struct StartFocusMenu: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var hovering = false

    var body: some View {
        Menu {
            Section(model.focusNames) {
                ForEach(FocusPane.lengths, id: \.0) { minutes, label in
                    Button(label) {
                        dismiss()
                        model.startFocus(minutes: minutes)
                    }
                }
            }
        } label: {
            PopoverRowLabel(symbol: "scope", title: "Start focus", trailing: nil, hovering: hovering)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .onHover { hovering = $0 }
    }
}

/// Circled SF Symbol at the start of a popover row.
private struct PopoverSymbol: View {
    let symbol: String
    @Environment(\.uiScale) private var scale

    var body: some View {
        Image(systemName: symbol)
            .scaledFont(14)
            .frame(width: 30 * scale, height: 30 * scale)
            .background(Color.primary.opacity(0.1), in: Circle())
    }
}

/// What a popover row shows: circled symbol, title, optional trailing text, hover highlight.
private struct PopoverRowLabel: View {
    let symbol: String
    let title: String
    let trailing: String?
    let hovering: Bool
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 12 * scale) {
            PopoverSymbol(symbol: symbol)
            Text(title)
            Spacer()
            if let trailing { Text(trailing).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10 * scale).padding(.vertical, 6 * scale)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10 * scale))
    }
}

/// Popover row that runs an action.
private struct PopoverRow: View {
    let symbol: String
    let title: String
    var trailing: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PopoverRowLabel(symbol: symbol, title: title, trailing: trailing, hovering: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
