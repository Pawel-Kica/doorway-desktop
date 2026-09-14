import SimpleBlockCore
import SwiftUI

/// Settings window: sidebar with General, Apps, History.
struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        NavigationSplitView {
            List(SettingsTab.allCases, selection: Binding(get: { model.settingsTab }, set: { if let tab = $0 { model.settingsTab = tab } })) { tab in
                Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
            }
            .navigationSplitViewColumnWidth(180)
        } detail: {
            switch model.settingsTab {
            case .general: GeneralPane(model: model)
            case .apps: AppsPane(model: model)
            case .history: HistoryPane(model: model)
            }
        }
        .frame(width: 760, height: 500)
    }
}

private struct GeneralPane: View {
    @ObservedObject var model: AppModel
    /// Monday first.
    private let weekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Stepper("\(model.minutesPerReason) min", value: $model.minutesPerReason, in: 1...120)
                } label: {
                    Text("Time per reason")
                    Text("Fixed from the moment you give a reason. When it ends, the app hides and asks again.")
                }
            }
            Section {
                HStack {
                    ForEach(weekdays, id: \.self) { day in
                        Toggle(Calendar.current.shortWeekdaySymbols[day - 1], isOn: dayBinding(day))
                            .toggleStyle(.button)
                    }
                }
                DatePicker("From", selection: timeBinding(\.from), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: timeBinding(\.to), displayedComponents: .hourAndMinute)
            } header: {
                Text("Schedule")
            } footer: {
                Text("Same From and To means all day. From later than To runs past midnight.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("General")
    }

    private func dayBinding(_ day: Int) -> Binding<Bool> {
        Binding(
            get: { model.schedule.days.contains(day) },
            set: { on in
                if on { model.schedule.days.insert(day) } else { model.schedule.days.remove(day) }
            })
    }

    /// Minutes since midnight shown as a time of day.
    private func timeBinding(_ key: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = model.schedule[keyPath: key]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date())!
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.schedule[keyPath: key] = parts.hour! * 60 + parts.minute!
            })
    }
}

private struct AppsPane: View {
    @ObservedObject var model: AppModel
    /// The entry being edited, nil while adding a site.
    @State private var editing: GatedApp?
    @State private var showingEditor = false
    @State private var showingError = false
    @State private var name = ""
    @State private var url = ""

    var body: some View {
        Form {
            Section {
                if model.gatedApps.isEmpty {
                    Text("No gated apps").foregroundStyle(.secondary)
                }
                ForEach(model.gatedApps) { app in
                    HStack(spacing: 12) {
                        AppIcon(app: app, size: 28)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.path).font(.caption).foregroundStyle(.secondary)
                            if app.isSite { WebAppStatus(model: model, site: app) }
                        }
                        Spacer()
                        Button("Edit…") { startEditing(app) }
                        Button("Remove") { model.gatedApps.removeAll { $0.id == app.id } }
                    }
                }
            } footer: {
                HStack {
                    Spacer()
                    Button("Add site…") { startEditing(nil) }
                    Button("Add app…") { model.addApps() }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Apps")
        .alert(editing == nil ? "Add site" : "Edit \(editing!.name)", isPresented: $showingEditor) {
            TextField("Name, e.g. Gmail", text: $name)
            if editing?.isSite ?? true {
                TextField("URL, e.g. mail.google.com", text: $url)
            }
            Button(editing == nil ? "Add" : "Save") { save() }
            Button("Cancel", role: .cancel) {}
        } message: {
            if editing?.isSite ?? true {
                Text("Gates the site's Chrome app, and every subdomain. Install it once from Chrome: menu › Cast, save and share › Install page as app. Chrome tabs stay free.")
            }
        }
        .alert("That URL didn't work", isPresented: $showingError) {
            Button("OK") {}
        } message: {
            Text("It needs a host like mail.google.com that isn't gated yet.")
        }
    }

    /// Opens the alert for a new site (nil) or an existing entry.
    private func startEditing(_ app: GatedApp?) {
        editing = app
        name = app?.name ?? ""
        url = app?.path ?? ""
        showingEditor = true
    }

    private func save() {
        let ok = if let editing {
            model.gatedApps.edit(id: editing.id, name: name, url: editing.isSite ? url : nil)
        } else {
            model.gatedApps.addSite(name: name, url: url)
        }
        showingError = !ok
    }
}

/// Under a site in Settings: which Chrome app it gates, or how to get one.
private struct WebAppStatus: View {
    @ObservedObject var model: AppModel
    let site: GatedApp

    var body: some View {
        let apps = model.webApps(for: site)
        if apps.isEmpty {
            HStack(spacing: 6) {
                Text("No Chrome app yet, so nothing is gated.").foregroundStyle(.orange)
                Button("Open in Chrome") { model.openInChrome(site) }
                    .buttonStyle(.link)
            }
            .font(.caption)
        } else {
            Text("Gates " + apps.map { $0.deletingPathExtension().lastPathComponent }.joined(separator: ", "))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct HistoryPane: View {
    @ObservedObject var model: AppModel

    private struct Row: Identifiable {
        let id: Int
        let entry: LogEntry
    }

    var body: some View {
        let rows = model.entries.enumerated().reversed().map { Row(id: $0.offset, entry: $0.element) }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(rows.count) entries in \((ReasonLog.defaultURL.path as NSString).abbreviatingWithTildeInPath)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Show in Finder") { model.showLogInFinder() }
            }
            Table(rows) {
                TableColumn("When") { Text($0.entry.ts.formatted(date: .abbreviated, time: .shortened)) }
                    .width(min: 120, ideal: 140)
                TableColumn("App") { Text($0.entry.app) }
                    .width(min: 60, ideal: 80)
                TableColumn("Kind") { Text($0.entry.kind.rawValue) }
                    .width(min: 60, ideal: 70)
                TableColumn("Reason") { Text($0.entry.reason ?? "").textSelection(.enabled) }
            }
        }
        .padding(20)
        .navigationTitle("History")
    }
}
