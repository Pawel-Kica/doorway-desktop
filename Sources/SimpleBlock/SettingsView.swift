import SimpleBlockCore
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case focus = "Focus", zone = "Zone", music = "Music", sessions = "Sessions", blocklists = "Blocklists", allowlists = "Allowlists",
         general = "General", history = "History"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .focus: "scope"
        case .zone: "moon"
        case .music: "music.note"
        case .sessions: "calendar"
        case .blocklists: "list.bullet.rectangle"
        case .allowlists: "checklist"
        case .general: "gearshape"
        case .history: "clock"
        }
    }
}

/// Settings window: sidebar with Focus, Zone, Music, Sessions, Blocklists, Allowlists, General, History, drawn at the
/// `uiScale` size.
/// ⌘+, ⌘− and ⌘0 change the size while it's open, ⌘B hides and shows the sidebar, ⌘[ and ⌘] go to the previous and
/// next tab. The window can't be resized, it's 960 x 680 times the scale.
struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(UIScale.key) private var scale = UIScale.standard
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        let size = UIScale.size(960, 680, scale: scale)
        NavigationSplitView(columnVisibility: $columns) {
            List(SettingsTab.allCases, selection: Binding(get: { model.settingsTab }, set: { if let tab = $0 { model.settingsTab = tab } })) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
                    .labelStyle(SidebarLabelStyle())
                    .scaledFont(15)
                    .padding(.vertical, 4 * scale)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(210 * scale)
            // ⌘B instead: the toolbar button's collapse and expand glitched the sidebar in this fixed-size window.
            .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch model.settingsTab {
                case .focus: FocusPane(model: model)
                case .zone: ZonePane(model: model)
                case .music: MusicPane()
                case .sessions: SessionsPane(model: model)
                case .blocklists:
                    ListsPane(model: model, noun: "Blocklist", example: "Messengers", lists: $model.rules.blocklists,
                              frozen: model.isFrozen(list:), delete: { model.rules.deleteBlocklist($0) })
                case .allowlists:
                    ListsPane(model: model, noun: "Allowlist", example: "Deep work", lists: $model.focusRules.allowlists,
                              allows: { lists in model.canChangeFocus { $0.allowlists = lists } },
                              delete: { model.focusRules.deleteAllowlist($0) })
                case .general: GeneralPane(model: model)
                case .history: HistoryPane(model: model)
                }
            }
            .scaledFont(15)
            .controlSize(UIScale.controlSize(scale))
        }
        // An exact size rather than a minimum: the window isn't resizable, so it shrinks back only this way.
        .frame(width: size.width, height: size.height)
        .background { SizeShortcuts(scale: $scale) }
        .background {
            Group {
                Button("Toggle sidebar") { withAnimation { columns = columns == .detailOnly ? .all : .detailOnly } }
                    .keyboardShortcut("b")
                // Work with the sidebar hidden too: they're on the window, not the list.
                Button("Previous tab") { model.settingsTab = model.settingsTab.stepped(by: -1) }.keyboardShortcut("[")
                Button("Next tab") { model.settingsTab = model.settingsTab.stepped(by: 1) }.keyboardShortcut("]")
            }
            .opacity(0).accessibilityHidden(true)
        }
        // Settings windows get the preferences toolbar: title on top, then an empty row meant for tab icons.
        .background { WindowReader { $0.toolbarStyle = .unifiedCompact } }
        .environment(\.uiScale, scale)
        // The window grows from its top left corner, which can push its bottom off the screen.
        .onChange(of: scale) { DispatchQueue.main.async { NSApp.keyWindow?.keepOnScreen() } }
    }
}

/// Hands the hosting window to `configure` once the view is in one.
private struct WindowReader: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window.map(configure) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
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
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(15)
                .opacity(isEnabled ? 1 : 0.35)
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

    /// Weekdays 8:00-19:00 on every blocklist, opened to edit. First in the list, right under the button:
    /// at the end it landed below the fold once a session was open.
    private func addSession() {
        let session = ScheduledSession(blocklists: Set(model.rules.blocklists.map(\.id)),
                                       schedule: Schedule(days: Set(2...6), from: 8 * 60, to: 19 * 60))
        model.rules.sessions.insert(session, at: 0)
        open.insert(session.id)
    }
}

/// A scheduled session folded to one row: chevron, its name (or blocklists), "18:00 to 10:00 · Every day" (plus a lock with super lock),
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
                    RowTitle(title: model.rules.title(session)) {
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
struct RowTitle<Detail: View>: View {
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
            // Not frozen with the rest: a name changes nothing about what's gated.
            CardRow {
                SettingRow(title: "Name") {
                    TextField(model.rules.names(session.blocklists), text: $session.name)
                        .frame(width: 320 * scale)
                }
            }
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
                            TimeField(minutes: session.schedule.from) { [id = session.id] in setTime(\.from, $0, of: id) }
                            Text("to").foregroundStyle(.secondary)
                            TimeField(minutes: session.schedule.to) { [id = session.id] in setTime(\.to, $0, of: id) }
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

    /// Saves a typed time by session ID, not through the binding: a field also saves as it goes away,
    /// which can be right after its session was deleted.
    private func setTime(_ end: WritableKeyPath<Schedule, Int>, _ minutes: Int, of id: UUID) {
        guard let index = model.rules.sessions.firstIndex(where: { $0.id == id }) else { return }
        model.rules.sessions[index].schedule[keyPath: end] = minutes
    }
}

/// A time of day as a text field ("18:00"): unlike DatePicker it grows with the UI scale. Enter, leaving the field or
/// it going away (fold, other tab) saves; anything that isn't a time goes back to the old value. Saving while typing
/// stored half-typed times ("19:3" as 19:03) and could switch a super lock on, freezing the session, mid-edit.
private struct TimeField: View {
    /// Minutes since midnight.
    let minutes: Int
    /// Gets the typed minutes when they differ.
    let save: (Int) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.uiScale) private var scale

    var body: some View {
        TextField("Time", text: $text)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { if !focused { commit() } }
            .onDisappear(perform: commit)
            .onAppear { text = clockText(minutes) }
            .onChange(of: minutes) { text = clockText(minutes) }
            .monospacedDigit()
            .multilineTextAlignment(.center)
            .frame(width: 76 * scale)
    }

    private func commit() {
        guard let typed = parseClock(text) else {
            text = clockText(minutes)
            return
        }
        text = clockText(typed)
        if typed != minutes { save(typed) }
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: AppModel
    @AppStorage(UIScale.key) private var scale = UIScale.standard
    @AppStorage(AppIconChoice.key) private var appIcon = AppIconChoice.scope.rawValue

    var body: some View {
        Pane {
            Card {
                CardRow(divider: false) {
                    SettingRow(title: "Time per reason",
                               note: "Fixed from the moment you give a reason. When it ends, the app hides and asks again.") {
                        // Buttons instead of a Stepper, which doesn't grow with the scale. The symbols go in a Text
                        // so both get a full line's height; a bare minus made a shorter button than the plus.
                        HStack(spacing: 8 * scale) {
                            Button { model.minutesPerReason -= 1 } label: { Text(Image(systemName: "minus")).bezelPadding() }
                                .disabled(model.minutesPerReason <= 1)
                                .accessibilityLabel("Less time")
                            Text("\(model.minutesPerReason) min").monospacedDigit().frame(minWidth: 64 * scale)
                            Button { model.minutesPerReason += 1 } label: { Text(Image(systemName: "plus")).bezelPadding() }
                                .disabled(model.minutesPerReason >= 120)
                                .accessibilityLabel("More time")
                        }
                    }
                }
                CardRow {
                    SettingRow(title: "App icon", note: "In the Dock, Finder and Raycast.") {
                        HStack(spacing: 4 * scale) {
                            ForEach(AppIconChoice.allCases) { choice in
                                Button {
                                    appIcon = choice.rawValue
                                    AppIconChoice.apply()
                                } label: {
                                    Image(nsImage: choice.image(pixels: 128))
                                        .resizable()
                                        .frame(width: 44 * scale, height: 44 * scale)
                                        .padding(2 * scale)
                                        .background(AppIconChoice(rawValue: appIcon) ?? .scope == choice ? Color.accentColor.opacity(0.35) : .clear,
                                                    in: RoundedRectangle(cornerRadius: 10 * scale))
                                }
                                .buttonStyle(.plain)
                                .help(choice.name)
                            }
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

/// The Blocklists and Allowlists tabs, same UI: a section per list with rename and delete in its title, its apps with
/// rename and remove, Add app… under each list, Add blocklist… (or allowlist) at the bottom.
private struct ListsPane: View {
    @ObservedObject var model: AppModel
    /// "Blocklist" or "Allowlist".
    let noun: String
    /// A name suggested when adding one.
    let example: String
    @Binding var lists: [Blocklist]
    /// Lists a super-locked session uses right now: they keep their apps and can't be deleted. Blocklists only.
    var frozen: (UUID) -> Bool = { _ in false }
    /// Whether the lists may lose an app or a list, given how they'd look after. Allowlists: focus keeps an app.
    var allows: ([Blocklist]) -> Bool = { _ in true }
    let delete: (UUID) -> Void
    @Environment(\.uiScale) private var scale
    /// The list whose title is being renamed in place.
    @State private var renamingList: UUID?
    /// The app entry being renamed in place, with its list.
    @State private var renamingApp: (list: UUID, app: String)?
    @State private var adding = false
    @State private var newName = ""

    var body: some View {
        Pane {
            ForEach($lists) { $list in
                let isFrozen = frozen(list.id)
                if renamingList == list.id {
                    NameField(name: list.name) { typed in
                        if let typed = typed?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty { list.name = typed }
                        renamingList = nil
                    }
                    .sectionTitleFont()
                    .padding(.top, 8 * scale)
                } else {
                SectionTitle(title: list.name) {
                    if isFrozen {
                        Label("Frozen while super locked", systemImage: "lock.fill")
                            .noteFont().foregroundStyle(.red).padding(.trailing, 10 * scale)
                    }
                    // Same spacing as the row buttons, so the icons line up in columns.
                    HStack(spacing: 14 * scale) {
                        IconButton(symbol: "pencil", help: "Rename \(noun.lowercased())") { renamingList = list.id }
                        IconButton(symbol: "trash", help: "Delete \(noun.lowercased())") { delete(list.id) }
                            .disabled(isFrozen || !allows(lists.filter { $0.id != list.id }))
                    }
                    .padding(.trailing, 14 * scale)
                }
                }
                Card {
                    if list.entries.isEmpty {
                        CardRow(divider: false) { Text("No apps").foregroundStyle(.secondary) }
                    }
                    ForEach(list.entries) { app in
                        CardRow(divider: app.id != list.entries.first?.id) {
                            HStack(spacing: 14 * scale) {
                                AppIcon(app: app, size: 32 * scale)
                                if renamingApp?.list == list.id && renamingApp?.app == app.id {
                                    NameField(name: app.name) { typed in
                                        if let typed { list.entries.rename(id: app.id, to: typed) }
                                        renamingApp = nil
                                    }
                                } else {
                                    Text(app.name)
                                }
                                Spacer()
                                IconButton(symbol: "pencil", help: "Rename") { renamingApp = (list.id, app.id) }
                                IconButton(symbol: "minus.circle", help: "Remove from \(list.name)") { list.entries.removeAll { $0.id == app.id } }
                                    .disabled(isFrozen || !allows(without(app.id, in: list.id)))
                            }
                            .padding(.vertical, -4 * scale)
                        }
                    }
                }
                HStack {
                    Spacer()
                    Button { addApps(to: list.id) } label: { Text("Add app…").bezelPadding() }
                }
                .padding(.bottom, 12 * scale)
            }
            if lists.isEmpty {
                Card { CardRow(divider: false) { Text("No \(noun.lowercased())s").foregroundStyle(.secondary) } }
            }
            HStack {
                Spacer()
                Button { newName = ""; adding = true } label: { Text("Add \(noun.lowercased())…").bezelPadding() }
            }
        }
        .navigationTitle("\(noun)s")
        .alert("Add \(noun.lowercased())", isPresented: $adding) {
            TextField("Name, e.g. \(example)", text: $newName)
            Button("Add") { addList() }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The lists with one app taken out of one list.
    private func without(_ app: String, in list: UUID) -> [Blocklist] {
        var after = lists
        for i in after.indices where after[i].id == list { after[i].entries.removeAll { $0.id == app } }
        return after
    }

    /// Adds apps picked in /Applications. Looked up by ID after the open panel, the list may be gone by then.
    private func addApps(to id: UUID) {
        let picked = model.pickApps()
        guard let index = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[index].entries.add(picked)
    }

    /// An empty name makes "Blocklist" (or "Allowlist").
    private func addList() {
        let typed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        lists.append(Blocklist(name: typed.isEmpty ? noun : typed))
    }
}

/// Renames in place: starts with the current name selected for typing, saves on Return or when it loses focus,
/// Esc cancels (`done` gets nil). A rename alert started empty on macOS, whatever its binding held.
struct NameField: View {
    let name: String
    let done: (String?) -> Void
    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .focused($focused)
            .onAppear {
                text = name
                DispatchQueue.main.async { focused = true }
            }
            .onSubmit { finish(text) }
            .onExitCommand { finish(nil) }
            .onChange(of: focused) { if !focused { finish(text) } }
            .frame(maxWidth: 420)
    }

    /// Once only: Return or Esc also takes the focus away, which would save a second time.
    private func finish(_ typed: String?) {
        guard !finished else { return }
        finished = true
        done(typed)
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
                    .padding(.bottom, 16 * scale)
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
