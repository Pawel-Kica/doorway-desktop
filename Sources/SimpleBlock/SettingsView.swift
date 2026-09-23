import SimpleBlockCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case focus = "Focus", sessions = "Sessions", blocklists = "Blocklists", general = "General", history = "History"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .focus: "scope"
        case .sessions: "calendar"
        case .blocklists: "list.bullet.rectangle"
        case .general: "gearshape"
        case .history: "clock"
        }
    }
}

/// Settings window: sidebar with Focus, Sessions, Blocklists, General, History, drawn at the `uiScale` size.
/// ⌘+, ⌘− and ⌘0 change the size while it's open.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(UIScale.key) private var scale = UIScale.standard

    var body: some View {
        let minSize = UIScale.size(960, 680, scale: scale)
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(get: { model.settingsTab }, set: { if let tab = $0 { model.settingsTab = tab } })) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
                    .labelStyle(SidebarLabelStyle())
                    .scaledFont(15)
                    .padding(.vertical, 4 * scale)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(210 * scale)
        } detail: {
            Group {
                switch model.settingsTab {
                case .focus: FocusPane(model: model)
                case .sessions: SessionsPane(model: model)
                case .blocklists: BlocklistsPane(model: model)
                case .general: GeneralPane(model: model)
                case .history: HistoryPane(model: model)
                }
            }
            .scaledFont(15)
            .controlSize(UIScale.controlSize(scale))
        }
        .frame(minWidth: minSize.width, minHeight: minSize.height)
        .background { SizeShortcuts(scale: $scale) }
        .environment(\.uiScale, scale)
    }
}

/// Sidebar icon in a column that grows with the scale. The system one is fixed, so big icons ran into the title.
private struct SidebarLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarLabel(configuration: configuration)
    }
}

private struct SidebarLabel: View {
    let configuration: LabelStyleConfiguration
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 8 * scale) {
            configuration.icon.frame(width: 22 * scale)
            configuration.title
        }
    }
}

/// Invisible buttons that carry the size shortcuts. ⌘= is ⌘+ without Shift.
private struct SizeShortcuts: View {
    @Binding var scale: Double

    var body: some View {
        Group {
            Button("Bigger") { scale = UIScale.stepped(scale, by: 1) }.keyboardShortcut("+")
            Button("Bigger") { scale = UIScale.stepped(scale, by: 1) }.keyboardShortcut("=")
            Button("Smaller") { scale = UIScale.stepped(scale, by: -1) }.keyboardShortcut("-")
            Button("Default size") { scale = UIScale.standard }.keyboardShortcut("0")
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// Pane building blocks, shared with FocusPane.swift.
extension View {
    /// Section titles in the panes.
    func sectionTitleFont() -> some View { scaledFont(20, weight: .semibold) }
    /// Hints and second lines under a row.
    func noteFont() -> some View { scaledFont(13) }
}

/// A pane's scrolling column. Stands in for a grouped Form, which stops growing at about 700 points wide
/// and so can't follow the UI scale.
struct Pane<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.uiScale) private var scale

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8 * scale) { content }
                .frame(maxWidth: 820 * scale)
                .padding(24 * scale)
                .frame(maxWidth: .infinity)
        }
    }
}

/// Rows on a rounded card, like a grouped Form section.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12 * scale))
            .overlay(RoundedRectangle(cornerRadius: 12 * scale).stroke(Color.primary.opacity(0.08)))
    }
}

/// One padded row of a card, with a separator above unless it's the first.
struct CardRow<Content: View>: View {
    var divider = true
    @ViewBuilder var content: Content
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(spacing: 0) {
            if divider { Divider().padding(.horizontal, 14 * scale) }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14 * scale).padding(.vertical, 10 * scale)
        }
    }
}

/// A settings row: title, and an optional note under it, on the left; controls on the right.
struct SettingRow<Controls: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var controls: Controls
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 16 * scale) {
            VStack(alignment: .leading, spacing: 3 * scale) {
                Text(title)
                if let note {
                    Text(note).noteFont().foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            controls
        }
    }
}

/// Title above a card, with optional controls on the right.
struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 6 * scale) {
            Text(title).sectionTitleFont().foregroundStyle(.primary)
            Spacer()
            trailing
        }
        .padding(.top, 8 * scale).padding(.leading, 4 * scale)
    }
}

/// Borderless SF Symbol button for small actions in titles and rows (rename, edit, remove). `help` is the tooltip.
struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(15)
                .frame(width: 30 * scale, height: 30 * scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Every session in one list, Freedom style. A scheduled session is one folded row (blocklists, schedule, status,
/// enabled switch); a click opens its editor below it. Running quick sessions follow in the same list.
private struct SessionsPane: View {
    @ObservedObject var model: AppModel
    /// Sessions shown open. View state only: the pane starts folded every time.
    @State private var open: Set<UUID> = []

    var body: some View {
        Pane {
            SectionTitle(title: "Sessions") {
                Button(action: addSession) {
                    Label("Add session", systemImage: "plus").bezelPadding()
                }
                .buttonStyle(.borderedProminent)
            }
            Card {
                ForEach($model.rules.sessions) { $session in
                    // A super-locked session that's on now is frozen: nothing about it can change until it ends.
                    let frozen = model.isFrozen(session)
                    let isOpen = open.contains(session.id)
                    CardRow(divider: session.id != model.rules.sessions.first?.id) {
                        SessionHeader(model: model, session: $session, open: isOpen, frozen: frozen) {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if isOpen { open.remove(session.id) } else { open.insert(session.id) }
                            }
                        }
                    }
                    if isOpen {
                        SessionEditor(model: model, session: $session, frozen: frozen) {
                            if let copy = model.rules.duplicateSession(session.id) { open.insert(copy) }
                        }
                    }
                }
                ForEach(model.rules.quickSessions) { quick in
                    CardRow(divider: !model.rules.sessions.isEmpty || quick.id != model.rules.quickSessions.first?.id) {
                        QuickSessionRow(model: model, quick: quick)
                    }
                }
                if model.rules.sessions.isEmpty && model.rules.quickSessions.isEmpty {
                    CardRow(divider: false) { Text("No sessions").foregroundStyle(.secondary) }
                }
            }
            Text("Same start and end means all day. An end before the start runs past midnight.")
                .noteFont().foregroundStyle(.secondary).padding(.leading, 4)
        }
        .navigationTitle("Sessions")
    }

    /// Weekdays 8:00-19:00 on every blocklist, opened to edit.
    private func addSession() {
        let session = ScheduledSession(blocklists: Set(model.rules.blocklists.map(\.id)),
                                       schedule: Schedule(days: Set(2...6), from: 8 * 60, to: 19 * 60))
        model.rules.sessions.append(session)
        open.insert(session.id)
    }
}

/// A scheduled session folded to one row: chevron, blocklists, "18:00 to 10:00 · Every day" (plus a lock with super lock),
/// then the status and the enabled switch. Clicking anywhere but the switch opens or folds it.
private struct SessionHeader: View {
    @ObservedObject var model: AppModel
    @Binding var session: ScheduledSession
    let open: Bool
    let frozen: Bool
    let toggle: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 16 * scale) {
            Button(action: toggle) {
                HStack(spacing: 12 * scale) {
                    Image(systemName: "chevron.right")
                        .scaledFont(13, weight: .semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(open ? 90 : 0))
                        .frame(width: 16 * scale)
                    RowTitle(title: model.rules.names(session.blocklists)) {
                        Text("\(times) · \(session.schedule.daysSummary())")
                        if session.superLock {
                            Image(systemName: "lock.fill").foregroundStyle(frozen ? Color.red : Color.secondary)
                        }
                    }
                    Spacer(minLength: 12 * scale)
                    status
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("Enabled", isOn: $session.enabled).toggleStyle(.scaledSwitch).labelsHidden()
                .disabled(frozen)
        }
    }

    /// "18:00 to 10:00", or "All day" when start and end are the same.
    private var times: String {
        let schedule = session.schedule
        return schedule.from == schedule.to ? "All day" : "\(clock(schedule.from)) to \(clock(schedule.to))"
    }

    private var status: StatusLabel {
        let now = model.now
        return switch session.status(at: now) {
        case .on(let end): StatusLabel(text: "\(timeLeft(end.timeIntervalSince(now))) left", tone: .on)
        case .alwaysOn: StatusLabel(text: "Always on", tone: .on)
        case .starts(let start):
            // The weekday only once it's more than a day away, like "Starts Mon 10:00".
            StatusLabel(text: start.timeIntervalSince(now) < 24 * 3600
                ? "Starts \(start.formatted(date: .omitted, time: .shortened))"
                : "Starts \(start.formatted(.dateTime.weekday(.abbreviated))) \(start.formatted(date: .omitted, time: .shortened))",
                tone: .waiting)
        case .off: StatusLabel(text: "Off", tone: .off)
        }
    }

    /// Minutes since midnight as a time of day.
    private func clock(_ minutes: Int) -> String {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())!
            .formatted(date: .omitted, time: .shortened)
    }
}

/// A running quick session in the sessions list: its blocklists, time left, End.
private struct QuickSessionRow: View {
    @ObservedObject var model: AppModel
    let quick: QuickSession
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 12 * scale) {
            Image(systemName: "timer")
                .scaledFont(13, weight: .semibold)
                .foregroundStyle(.secondary)
                .frame(width: 16 * scale)
            RowTitle(title: model.rules.names(quick.blocklists)) {
                Text("Quick session until \(quick.ends.formatted(date: .omitted, time: .shortened))")
            }
            Spacer(minLength: 12 * scale)
            StatusLabel(text: "\(timeLeft(quick.ends.timeIntervalSince(model.now))) left", tone: .on)
            Button { model.endQuickSession(quick.id) } label: { Text("End").bezelPadding() }
                .padding(.leading, 4 * scale)
        }
    }
}

/// Session title in semibold with a secondary line under it.
private struct RowTitle<Detail: View>: View {
    let title: String
    @ViewBuilder var detail: Detail
    @Environment(\.uiScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * scale) {
            Text(title).scaledFont(17, weight: .semibold).lineLimit(1)
            HStack(spacing: 6 * scale) { detail }
                .noteFont().foregroundStyle(.secondary)
        }
    }
}

/// Status on the right of a session row: green dot while on, secondary while waiting, dimmed when off.
private struct StatusLabel: View {
    enum Tone { case on, waiting, off }
    let text: String
    let tone: Tone
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 8 * scale) {
            if tone == .on {
                Circle().fill(.green).frame(width: 9 * scale, height: 9 * scale)
            }
            Text(text).monospacedDigit().lineLimit(1)
        }
        .scaledFont(15, weight: tone == .on ? .semibold : .regular)
        .foregroundStyle(tone == .on ? HierarchicalShapeStyle.primary : tone == .waiting ? .secondary : .tertiary)
    }
}

/// An open session's rows under its header: days, time range, blocklists and super lock (days and blocklists as
/// toggle chips), then Duplicate and Delete. Indented so they read as part of the session.
/// Frozen: everything but Duplicate is disabled and Delete is gone.
private struct SessionEditor: View {
    @ObservedObject var model: AppModel
    @Binding var session: ScheduledSession
    let frozen: Bool
    let duplicate: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        Group {
            Group {
                CardRow {
                    SettingRow(title: "Days") {
                        HStack(spacing: 6 * scale) {
                            ForEach(Schedule.mondayFirst, id: \.self) { day in
                                Toggle(isOn: Binding(
                                    get: { session.schedule.days.contains(day) },
                                    set: { on in
                                        if on { session.schedule.days.insert(day) } else { session.schedule.days.remove(day) }
                                    })) { Text(Calendar.current.shortWeekdaySymbols[day - 1]).bezelPadding() }
                                .toggleStyle(.button)
                            }
                        }
                    }
                }
                CardRow {
                    SettingRow(title: "Time") {
                        HStack(spacing: 10 * scale) {
                            TimeField(minutes: $session.schedule.from)
                            Text("to").foregroundStyle(.secondary)
                            TimeField(minutes: $session.schedule.to)
                        }
                    }
                }
                CardRow {
                    SettingRow(title: "Blocklists") {
                        HStack(spacing: 6 * scale) {
                            if model.rules.blocklists.isEmpty { Text("No blocklists").foregroundStyle(.secondary) }
                            ForEach(model.rules.blocklists) { list in
                                Toggle(isOn: Binding(
                                    get: { session.blocklists.contains(list.id) },
                                    set: { on in
                                        if on { session.blocklists.insert(list.id) } else { session.blocklists.remove(list.id) }
                                    })) { Text(list.name).bezelPadding() }
                                .toggleStyle(.button)
                            }
                        }
                    }
                }
                CardRow {
                    SettingRow(title: "Super lock",
                               note: "Apps never open while it's on, no reason asked. The session can't be changed until it ends.") {
                        Toggle("Super lock", isOn: $session.superLock).toggleStyle(.scaledSwitch).labelsHidden()
                    }
                }
            }
            .disabled(frozen)
            CardRow {
                HStack(spacing: 14 * scale) {
                    if frozen {
                        Label("Frozen while super locked", systemImage: "lock.fill")
                            .noteFont().foregroundStyle(.red)
                    }
                    Spacer()
                    IconButton(symbol: "doc.on.doc", help: "Duplicate session", action: duplicate)
                    if !frozen {
                        IconButton(symbol: "trash", help: "Delete session") { model.rules.sessions.removeAll { $0.id == session.id } }
                    }
                }
                .padding(.vertical, -4 * scale)
            }
        }
        .padding(.leading, 28 * scale)
    }
}

/// A time of day as a text field ("18:00"): unlike DatePicker it grows with the UI scale. Enter or leaving it saves,
/// anything that isn't a time goes back to the old value.
private struct TimeField: View {
    /// Minutes since midnight.
    @Binding var minutes: Int
    @Environment(\.uiScale) private var scale

    var body: some View {
        TextField("Time", value: Binding(
            get: { Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())! },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes = parts.hour! * 60 + parts.minute!
            }), format: .dateTime.hour().minute())
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 76 * scale)
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: AppModel
    @AppStorage(UIScale.key) private var scale = UIScale.standard

    var body: some View {
        Pane {
            Card {
                CardRow(divider: false) {
                    SettingRow(title: "Time per reason",
                               note: "Fixed from the moment you give a reason. When it ends, the app hides and asks again.") {
                        // Buttons instead of a Stepper, which doesn't grow with the scale.
                        HStack(spacing: 8 * scale) {
                            Button { model.minutesPerReason -= 1 } label: { Image(systemName: "minus").bezelPadding() }
                                .disabled(model.minutesPerReason <= 1)
                                .accessibilityLabel("Less time")
                            Text("\(model.minutesPerReason) min").monospacedDigit().frame(minWidth: 64 * scale)
                            Button { model.minutesPerReason += 1 } label: { Image(systemName: "plus").bezelPadding() }
                                .disabled(model.minutesPerReason >= 120)
                                .accessibilityLabel("More time")
                        }
                    }
                }
                CardRow {
                    SettingRow(title: "Size", note: "⌘+ and ⌘− also work, ⌘0 goes back to \(Int(UIScale.standard * 100))%.") {
                        // Chips instead of a segmented picker, which doesn't grow with the scale.
                        HStack(spacing: 6 * scale) {
                            ForEach(UIScale.choices, id: \.self) { choice in
                                Toggle(isOn: Binding(get: { scale == choice }, set: { if $0 { scale = choice } })) {
                                    Text("\(Int((choice * 100).rounded()))%").bezelPadding()
                                }
                                .toggleStyle(.button)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("General")
    }
}

private struct BlocklistsPane: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiScale) private var scale
    /// Blocklist the rename alert works on.
    @State private var target: UUID?
    /// The app being renamed.
    @State private var editing: GatedApp?
    @State private var showingEditor = false
    @State private var name = ""
    /// The blocklist being renamed, nil while adding one.
    @State private var renaming: Blocklist?
    @State private var showingNamer = false
    @State private var listName = ""

    var body: some View {
        Pane {
            ForEach($model.rules.blocklists) { $list in
                // A list a super-locked session uses right now keeps its apps and can't be deleted.
                let frozen = model.isFrozen(list: list.id)
                SectionTitle(title: list.name) {
                    if frozen {
                        Label("Frozen while super locked", systemImage: "lock.fill")
                            .noteFont().foregroundStyle(.red).padding(.trailing, 10 * scale)
                    }
                    // Same spacing as the row buttons, so the icons line up in columns.
                    HStack(spacing: 14 * scale) {
                        IconButton(symbol: "pencil", help: "Rename blocklist") { startNaming(list) }
                        IconButton(symbol: "trash", help: "Delete blocklist") { model.rules.deleteBlocklist(list.id) }
                            .disabled(frozen)
                    }
                    .padding(.trailing, 14 * scale)
                }
                Card {
                    if list.entries.isEmpty {
                        CardRow(divider: false) { Text("No apps").foregroundStyle(.secondary) }
                    }
                    ForEach(list.entries) { app in
                        CardRow(divider: app.id != list.entries.first?.id) {
                            HStack(spacing: 14 * scale) {
                                AppIcon(app: app, size: 32 * scale)
                                Text(app.name)
                                Spacer()
                                IconButton(symbol: "pencil", help: "Rename") { startEditing(app, in: list.id) }
                                IconButton(symbol: "minus.circle", help: "Remove from \(list.name)") { list.entries.removeAll { $0.id == app.id } }
                                    .disabled(frozen)
                            }
                            .padding(.vertical, -4 * scale)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button { model.addApps(to: list.id) } label: { Text("Add app…").bezelPadding() }
                }
                .padding(.bottom, 12 * scale)
            }
            if model.rules.blocklists.isEmpty {
                Card { CardRow(divider: false) { Text("No blocklists").foregroundStyle(.secondary) } }
            }
            HStack {
                Spacer()
                Button { startNaming(nil) } label: { Text("Add blocklist…").bezelPadding() }
            }
        }
        .navigationTitle("Blocklists")
        .alert("Rename \(editing?.name ?? "")", isPresented: $showingEditor) {
            TextField("Name, e.g. Signal", text: $name)
            Button("Save") { save() }
            Button("Cancel", role: .cancel) {}
        }
        .alert(renaming == nil ? "Add blocklist" : "Rename \(renaming!.name)", isPresented: $showingNamer) {
            TextField("Name, e.g. Messengers", text: $listName)
            Button(renaming == nil ? "Add" : "Save") { saveName() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Opens the rename alert for an app of a blocklist.
    private func startEditing(_ app: GatedApp, in list: UUID) {
        target = list
        editing = app
        name = app.name
        showingEditor = true
    }

    private func save() {
        guard let editing, let index = model.rules.blocklists.firstIndex(where: { $0.id == target }) else { return }
        model.rules.blocklists[index].entries.rename(id: editing.id, to: name)
    }

    /// Opens the name alert for a new blocklist (nil) or a rename.
    private func startNaming(_ list: Blocklist?) {
        renaming = list
        listName = list?.name ?? ""
        showingNamer = true
    }

    /// An empty name keeps the old one, or makes "Blocklist" for a new list.
    private func saveName() {
        let typed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let renaming {
            guard !typed.isEmpty, let index = model.rules.blocklists.firstIndex(where: { $0.id == renaming.id }) else { return }
            model.rules.blocklists[index].name = typed
        } else {
            model.rules.blocklists.append(Blocklist(name: typed.isEmpty ? "Blocklist" : typed))
        }
    }
}

/// The dashboard (KPI tiles and charts), then the log newest first, grouped by day (Today, Yesterday, then dates).
/// Each day is a card: app icon, name, kind pill, time, the full reason. One lazy scrolling column, so a long log stays quick.
private struct HistoryPane: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiScale) private var scale

    private struct Row: Identifiable {
        let id: Int
        let entry: LogEntry
    }

    private struct Day: Identifiable {
        let id: Date
        var rows: [Row]
    }

    var body: some View {
        let known = model.rules.everyEntry
        let days = days()
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8 * scale) {
                HistoryDashboard(entries: model.entries, now: model.now, scale: scale)
                HStack {
                    Text("\(model.entries.count) entries in \((ReasonLog.defaultURL.path as NSString).abbreviatingWithTildeInPath)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { model.showLogInFinder() } label: { Text("Show in Finder").bezelPadding() }
                }
                .padding(.top, 16 * scale).padding(.bottom, 8 * scale)
                if days.isEmpty {
                    Text("No reasons yet").foregroundStyle(.secondary)
                }
                ForEach(days) { day in
                    Text(title(day.id))
                        .scaledFont(13, weight: .semibold).foregroundStyle(.secondary)
                        .padding(.leading, 4 * scale).padding(.top, day.id == days.first?.id ? 0 : 14 * scale)
                    Card {
                        ForEach(day.rows) { row in
                            HistoryRow(entry: row.entry, app: known.first { $0.bundleId == row.entry.bundleId })
                            if row.id != day.rows.last?.id { Divider().padding(.leading, 58 * scale) }
                        }
                    }
                }
            }
            .frame(maxWidth: 820 * scale)
            .padding(24 * scale)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("History")
    }

    /// Entries newest first, split where the day changes.
    private func days() -> [Day] {
        var days: [Day] = []
        for (index, entry) in model.entries.enumerated().reversed() {
            let day = Calendar.current.startOfDay(for: entry.ts)
            if days.last?.id == day {
                days[days.count - 1].rows.append(Row(id: index, entry: entry))
            } else {
                days.append(Day(id: day, rows: [Row(id: index, entry: entry)]))
            }
        }
        return days
    }

    private func title(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: model.now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: model.now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

/// One log entry. Focus shows a scope and how long it ran on which apps, only reason kinds show a reason.
private struct HistoryRow: View {
    let entry: LogEntry
    /// The blocklist entry it's for, if it's still in one. Gives the icon.
    let app: GatedApp?
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(alignment: .top, spacing: 14 * scale) {
            icon.frame(width: 28 * scale, height: 28 * scale)
            VStack(alignment: .leading, spacing: 4 * scale) {
                HStack(spacing: 8 * scale) {
                    Text(entry.app).fontWeight(.semibold)
                    KindPill(kind: entry.kind)
                    Spacer()
                    Text(entry.ts.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit().noteFont().foregroundStyle(.secondary)
                }
                if entry.kind == .focus {
                    // "25 min on Obsidian, Todoist"
                    Text([entry.minutes.map(durationText), entry.reason].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " on "))
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if entry.kind.hasReason, let reason = entry.reason {
                    Text(reason).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16 * scale).padding(.vertical, 12 * scale)
    }

    /// The app's icon, from its blocklist entry or else wherever it's installed (apps a focus hid aren't in a blocklist).
    @ViewBuilder private var icon: some View {
        let installed = app ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: entry.bundleId)
            .map { GatedApp(bundleId: entry.bundleId, name: entry.app, path: $0.path) }
        switch entry.kind {
        case .focus: Image(systemName: "scope").scaledFont(18).foregroundStyle(.secondary)
        case .quit: Image(systemName: "hand.raised.fill").scaledFont(18).foregroundStyle(.secondary)
        default:
            if let installed {
                AppIcon(app: installed, size: 28 * scale)
            } else {
                Image(systemName: "app.dashed").scaledFont(18).foregroundStyle(.secondary)
            }
        }
    }
}

private struct KindPill: View {
    let kind: LogKind
    @Environment(\.uiScale) private var scale

    var body: some View {
        let color: Color = switch kind {
        case .launch, .switch: .blue
        case .expired: .orange
        case .locked: .red
        case .hidden: .purple
        case .focus: .green
        case .cancelled, .quit: .gray
        }
        Text(kind.rawValue)
            .scaledFont(12, weight: .semibold)
            .foregroundStyle(color)
            .padding(.horizontal, 8 * scale).padding(.vertical, 2 * scale)
            .background(color.opacity(0.16), in: Capsule())
    }
}
