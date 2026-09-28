import SwiftUI

/// Today's numbers and entries, the four rules, and how to set up the Shortcuts automation.
struct HomeView: View {
    @Bindable private var model = Model.shared

    var body: some View {
        let now = Date.now
        let state = model.state
        NavigationStack {
            Form {
                Section("Today") {
                    LabeledContent("Opened", value: "\(state.opensToday(now: now))")
                    LabeledContent("Short reasons left", value: "\(state.shortLeft(now: now))")
                    LabeledContent("Resisted", value: "\(state.resistedToday(now: now))")
                    LabeledContent("Next reason needs", value: "\(state.requiredWords(now: now)) words")
                    ForEach(state.entriesToday(now: now).reversed(), id: \.date) { EntryRow(entry: $0) }
                }
                Section("Rules") {
                    rule("Short reasons per day", $model.state.settings.shortPerDay, 0...50)
                    rule("Short reason words", $model.state.settings.shortWords, 1...50)
                    rule("Long reason words", $model.state.settings.longWords, 1...200)
                    rule("Unlocked for", $model.state.settings.unlockMinutes, 1...60, unit: " min")
                }
                Section {
                    step(1, "Shortcuts > Automation > + > App.")
                    step(2, "Pick Signal, check Is Opened, choose Run Immediately, turn Notify When Run off, tap Next.")
                    step(3, "New Blank Automation, add Gate App from Simple Block, set App to Signal.")
                    step(4, "Repeat for each app you want to gate.")
                } header: {
                    Text("Setup")
                } footer: {
                    Text("Plan B, if Gate App asks for confirmation every time: make the automation Needs Reason (App: Signal), then If Result is true, then Ask Reason (App: Signal).")
                }
            }
            .navigationTitle("Simple Block")
        }
    }

    private func rule(_ title: String, _ value: Binding<Int>, _ range: ClosedRange<Int>, unit: String = "") -> some View {
        Stepper(value: value, in: range) {
            LabeledContent(title, value: "\(value.wrappedValue)\(unit)")
        }
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)").monospacedDigit().foregroundStyle(.secondary)
            Text(text)
        }
    }
}

/// One of today's entries: time, app, and the reason (or that it was resisted).
private struct EntryRow: View {
    let entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.app.name).fontWeight(.medium)
                Spacer()
                Text(entry.date, format: .dateTime.hour().minute()).foregroundStyle(.secondary).monospacedDigit()
            }
            if let reason = entry.reason {
                Text(reason).foregroundStyle(.secondary)
            } else {
                Text("Never mind").foregroundStyle(.tertiary).italic()
            }
        }
    }
}
