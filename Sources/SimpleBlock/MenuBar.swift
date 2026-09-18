import SimpleBlockCore
import SwiftUI

/// Menu bar icon, plus "Signal 3:12" while a timer runs (the one ending first).
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: "hand.raised.fill")
        if let running = model.timers.soonest(now: model.now),
           let app = model.everyEntry.first(where: { $0.bundleId == running.bundleId }) {
            Text("\(app.name) \(countdown(running.remaining))")
        }
    }
}

/// The menu bar popover: what gates now, gated apps with timers, quick sessions, Start session, today's count, Settings, Quit.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let gated = model.gated(at: model.now)
        let status = status()
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Simple Block").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text(status.text)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .foregroundStyle(status.on ? .green : .orange)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background((status.on ? Color.green : Color.orange).opacity(0.18), in: Capsule())
            }
            .padding(.horizontal, 8).padding(.bottom, 10)

            if gated.isEmpty {
                Text("Nothing gated now").foregroundStyle(.secondary).padding(10)
            }
            // A running timer shows its countdown, everything else a lock: it asks for a reason.
            ForEach(gated) { app in
                let left = model.timers.remaining(app.bundleId, now: model.now)
                HStack(spacing: 12) {
                    AppIcon(app: app, size: 30)
                    Text(app.name)
                    Spacer()
                    if left > 0 {
                        Text("\(countdown(left)) left").monospacedDigit()
                    } else {
                        Image(systemName: "lock.fill").font(.system(size: 13)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
            }

            Divider().padding(.vertical, 8)
            ForEach(model.quickSessions) { quick in
                HStack(spacing: 12) {
                    PopoverSymbol(symbol: "timer")
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.names(quick.blocklists)).lineLimit(1)
                        Text("\(countdown(quick.ends.timeIntervalSince(model.now))) left")
                            .font(.system(size: 13)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("End") { model.endQuickSession(quick.id) }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            if !model.blocklists.isEmpty { StartSessionMenu(model: model) }
            PopoverRow(symbol: "list.bullet", title: "Today's reasons",
                       trailing: "\(reasonsToday(model.entries, now: model.now))") { open(.history) }
            PopoverRow(symbol: "gearshape", title: "Settings…") { open(.sessions) }
            PopoverRow(symbol: "power", title: "Quit") { model.quit() }
        }
        .font(.system(size: 15))
        .padding(14)
        .frame(width: 360)
    }

    /// What gates now: a scheduled session first (they're the main thing), else the quick session ending last.
    private func status() -> (text: String, on: Bool) {
        if let session = activeSessions(model.sessions, now: model.now).first {
            let schedule = session.schedule
            guard schedule.from != schedule.to else { return ("Session on all day", true) }
            let end = Calendar.current.date(bySettingHour: schedule.to / 60, minute: schedule.to % 60, second: 0, of: model.now)!
            return ("Session on until \(end.formatted(date: .omitted, time: .shortened))", true)
        }
        if let quick = model.quickSessions.filter({ $0.ends > model.now }).max(by: { $0.ends < $1.ends }) {
            return ("Quick session, \(countdown(quick.ends.timeIntervalSince(model.now))) left", true)
        }
        return ("No session now", false)
    }

    private func open(_ tab: SettingsTab) {
        model.settingsTab = tab
        dismiss()
        openSettings()
        NSApp.activate()
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
            if model.blocklists.count > 1 {
                lengthMenu("All blocklists", Set(model.blocklists.map(\.id)))
                Divider()
            }
            ForEach(model.blocklists) { list in lengthMenu(list.name, [list.id]) }
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

/// Circled SF Symbol at the start of a popover row.
private struct PopoverSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14))
            .frame(width: 30, height: 30)
            .background(Color.primary.opacity(0.1), in: Circle())
    }
}

/// What a popover row shows: circled symbol, title, optional trailing text, hover highlight.
private struct PopoverRowLabel: View {
    let symbol: String
    let title: String
    let trailing: String?
    let hovering: Bool

    var body: some View {
        HStack(spacing: 12) {
            PopoverSymbol(symbol: symbol)
            Text(title)
            Spacer()
            if let trailing { Text(trailing).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
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
