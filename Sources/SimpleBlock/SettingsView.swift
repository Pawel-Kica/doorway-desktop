import SimpleBlockCore
import SwiftUI

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

/// Settings window: sidebar with Sessions, Blocklists, General, History.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(get: { model.settingsTab }, set: { if let tab = $0 { model.settingsTab = tab } })) { tab in
                Label(tab.rawValue, systemImage: tab.symbol)
                    .font(.system(size: 15))
                    .padding(.vertical, 4)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(210)
        } detail: {
            Group {
                switch model.settingsTab {
                case .sessions: SessionsPane(model: model)
                case .blocklists: BlocklistsPane(model: model)
                case .general: GeneralPane(model: model)
                case .history: HistoryPane(model: model)
                }
            }
            .font(.system(size: 15))
            .controlSize(.large)
        }
        .frame(minWidth: 960, minHeight: 680)
    }
}

private extension Font {
    /// Section titles in the panes.
    static let sectionTitle = Font.system(size: 20, weight: .semibold)
    /// Hints and second lines under a row.
    static let note = Font.system(size: 13)
}

/// Title above a grouped section, with optional controls on the right.
private struct SectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.sectionTitle).foregroundStyle(.primary)
            Spacer()
            trailing
        }
        .padding(.top, 8).padding(.bottom, 4)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// Borderless SF Symbol button for small actions in titles and rows (rename, edit, remove). `help` is the tooltip.
private struct IconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct SessionsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            ForEach($model.rules.sessions) { $session in
                // A super-locked session that's on now is frozen: nothing about it can change until it ends.
                let frozen = model.isFrozen(session)
                Section {
                    SessionRows(model: model, session: $session)
                } header: {
                    SectionTitle(title: model.rules.names(session.blocklists)) {
                        if frozen {
                            Label("Frozen while super locked", systemImage: "lock.fill")
                                .font(.note).foregroundStyle(.red).padding(.trailing, 10)
                        }
                        Toggle("Enabled", isOn: $session.enabled).toggleStyle(.switch).labelsHidden()
                            .padding(.trailing, 6)
                        IconButton(symbol: "trash", help: "Delete session") { model.rules.sessions.removeAll { $0.id == session.id } }
                    }
                    .disabled(frozen)
                }
                .disabled(frozen)
            }
            Section {
                if model.rules.sessions.isEmpty {
                    Text("No sessions").foregroundStyle(.secondary)
                }
            } footer: {
                HStack {
                    Text("Same start and end means all day. An end before the start runs past midnight.")
                        .font(.note).foregroundStyle(.secondary)
                    Spacer()
                    Button("Add session") {
                        // Weekdays 8:00-19:00 on every blocklist.
                        model.rules.sessions.append(ScheduledSession(blocklists: Set(model.rules.blocklists.map(\.id)),
                                                                     schedule: Schedule(days: [2, 3, 4, 5, 6], from: 8 * 60, to: 19 * 60)))
                    }
                }
            }
            if !model.rules.quickSessions.isEmpty {
                Section {
                    ForEach(model.rules.quickSessions) { quick in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(model.rules.names(quick.blocklists))
                                Text("\(countdown(quick.ends.timeIntervalSince(model.now))) left")
                                    .font(.note).monospacedDigit().foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("End") { model.endQuickSession(quick.id) }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    SectionTitle("Quick sessions")
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Sessions")
    }
}

/// One scheduled session's days, time range and blocklists, the last two as toggle chips like the days.
private struct SessionRows: View {
    @ObservedObject var model: AppModel
    @Binding var session: ScheduledSession
    /// Monday first.
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        LabeledContent("Days") {
            HStack {
                ForEach(weekdays, id: \.self) { day in
                    Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: Binding(
                        get: { session.schedule.days.contains(day) },
                        set: { on in
                            if on { session.schedule.days.insert(day) } else { session.schedule.days.remove(day) }
                        }))
                    .toggleStyle(.button)
                }
            }
        }
        LabeledContent("Time") {
            HStack(spacing: 10) {
                DatePicker("From", selection: timeBinding(\.from), displayedComponents: .hourAndMinute).labelsHidden()
                Text("to").foregroundStyle(.secondary)
                DatePicker("To", selection: timeBinding(\.to), displayedComponents: .hourAndMinute).labelsHidden()
            }
        }
        LabeledContent("Blocklists") {
            HStack {
                if model.rules.blocklists.isEmpty { Text("No blocklists").foregroundStyle(.secondary) }
                ForEach(model.rules.blocklists) { list in
                    Toggle(list.name, isOn: Binding(
                        get: { session.blocklists.contains(list.id) },
                        set: { on in
                            if on { session.blocklists.insert(list.id) } else { session.blocklists.remove(list.id) }
                        }))
                    .toggleStyle(.button)
                }
            }
        }
        LabeledContent {
            Toggle("Super lock", isOn: $session.superLock).toggleStyle(.switch).labelsHidden()
        } label: {
            Text("Super lock")
            Text("Apps never open while it's on, no reason asked. The session can't be changed until it ends.")
                .font(.note)
        }
    }

    /// Minutes since midnight shown as a time of day.
    private func timeBinding(_ key: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = session.schedule[keyPath: key]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())!
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                session.schedule[keyPath: key] = parts.hour! * 60 + parts.minute!
            })
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("\(model.minutesPerReason) min").monospacedDigit()
                        Stepper("Time per reason", value: $model.minutesPerReason, in: 1...120).labelsHidden()
                    }
                } label: {
                    Text("Time per reason")
                    Text("Fixed from the moment you give a reason. When it ends, the app hides and asks again.")
                        .font(.note)
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }
}

private struct BlocklistsPane: View {
    @ObservedObject var model: AppModel
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
        Form {
            ForEach($model.rules.blocklists) { $list in
                // A list a super-locked session uses right now keeps its apps and can't be deleted.
                let frozen = model.isFrozen(list: list.id)
                Section {
                    if list.entries.isEmpty {
                        Text("No apps").foregroundStyle(.secondary)
                    }
                    ForEach(list.entries) { app in
                        HStack(spacing: 14) {
                            AppIcon(app: app, size: 32)
                            Text(app.name)
                            Spacer()
                            IconButton(symbol: "pencil", help: "Rename") { startEditing(app, in: list.id) }
                            IconButton(symbol: "minus.circle", help: "Remove from \(list.name)") { list.entries.removeAll { $0.id == app.id } }
                                .disabled(frozen)
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    SectionTitle(title: list.name) {
                        if frozen {
                            Label("Frozen while super locked", systemImage: "lock.fill")
                                .font(.note).foregroundStyle(.red).padding(.trailing, 10)
                        }
                        // Same spacing as the row buttons, so the icons line up in columns.
                        HStack(spacing: 14) {
                            IconButton(symbol: "pencil", help: "Rename blocklist") { startNaming(list) }
                            IconButton(symbol: "trash", help: "Delete blocklist") { model.rules.deleteBlocklist(list.id) }
                                .disabled(frozen)
                        }
                    }
                } footer: {
                    HStack {
                        Spacer()
                        Button("Add app…") { model.addApps(to: list.id) }
                    }
                }
            }
            Section {
                if model.rules.blocklists.isEmpty {
                    Text("No blocklists").foregroundStyle(.secondary)
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Add blocklist…") { startNaming(nil) }
                }
            }
        }
        .formStyle(.grouped)
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

/// Newest first, grouped by day (Today, Yesterday, then dates). Each day is a card: app icon, name, kind pill, time, the full reason.
private struct HistoryPane: View {
    @ObservedObject var model: AppModel

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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(model.entries.count) entries in \((ReasonLog.defaultURL.path as NSString).abbreviatingWithTildeInPath)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Show in Finder") { model.showLogInFinder() }
            }
            if days.isEmpty {
                Text("No reasons yet").foregroundStyle(.secondary)
                Spacer()
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(days) { day in
                        Text(title(day.id))
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                            .padding(.leading, 4).padding(.top, day.id == days.first?.id ? 0 : 14)
                        VStack(spacing: 0) {
                            ForEach(day.rows) { row in
                                HistoryRow(entry: row.entry, app: known.first { $0.bundleId == row.entry.bundleId })
                                if row.id != day.rows.last?.id { Divider().padding(.leading, 58) }
                            }
                        }
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
                    }
                }
            }
        }
        .padding(24)
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

private struct HistoryRow: View {
    let entry: LogEntry
    /// The blocklist entry it's for, if it's still in one. Gives the icon.
    let app: GatedApp?

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if let app {
                    AppIcon(app: app, size: 28)
                } else {
                    Image(systemName: entry.kind == .quit ? "hand.raised.fill" : "app.dashed")
                        .font(.system(size: 18)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(entry.app).fontWeight(.semibold)
                    KindPill(kind: entry.kind)
                    Spacer()
                    Text(entry.ts.formatted(date: .omitted, time: .shortened))
                        .font(.note).monospacedDigit().foregroundStyle(.secondary)
                }
                if let reason = entry.reason {
                    Text(reason).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

private struct KindPill: View {
    let kind: LogKind

    var body: some View {
        let color: Color = switch kind {
        case .launch, .switch: .blue
        case .expired: .orange
        case .locked: .red
        case .cancelled, .quit: .gray
        }
        Text(kind.rawValue)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
    }
}
