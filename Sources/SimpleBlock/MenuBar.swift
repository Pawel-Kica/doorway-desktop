import SimpleBlockCore
import SwiftUI

/// Menu bar icon, plus "Signal 3:12" while a timer runs (the one ending first).
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Image(systemName: "hand.raised.fill")
        if let running = model.timers.soonest(now: model.now),
           let app = model.gatedApps.first(where: { $0.bundleId == running.bundleId }) {
            Text("\(app.name) \(countdown(running.remaining))")
        }
    }
}

/// The menu bar popover: status, gated apps with timers, today's count, Settings, Quit.
struct PopoverView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let active = model.schedule.isActive(at: model.now)
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Simple Block").font(.headline)
                Spacer()
                Text(active ? "Active now" : "Off now")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(active ? .green : .orange)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background((active ? Color.green : Color.orange).opacity(0.18), in: Capsule())
            }
            .padding(.horizontal, 6).padding(.bottom, 8)

            if model.gatedApps.isEmpty {
                Text("No gated apps").foregroundStyle(.secondary).padding(8)
            }
            ForEach(model.gatedApps) { app in
                let left = model.timers.remaining(app.bundleId, now: model.now)
                HStack(spacing: 10) {
                    AppIcon(app: app, size: 26)
                    Text(app.name)
                    Spacer()
                    Text(left > 0 ? "\(countdown(left)) left" : "Asks for reason")
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
            }

            Divider().padding(.vertical, 6)
            PopoverRow(symbol: "list.bullet", title: "Today's reasons",
                       trailing: "\(reasonsToday(model.entries, now: model.now))") { open(.history) }
            PopoverRow(symbol: "gearshape", title: "Settings…") { open(.general) }
            PopoverRow(symbol: "power", title: "Quit") { model.quit() }
        }
        .padding(12)
        .frame(width: 300)
    }

    private func open(_ tab: SettingsTab) {
        model.settingsTab = tab
        dismiss()
        openSettings()
        NSApp.activate()
    }
}

/// Popover row: circled SF Symbol, title, optional trailing text. Highlights on hover.
private struct PopoverRow: View {
    let symbol: String
    let title: String
    var trailing: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12))
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.1), in: Circle())
                Text(title)
                Spacer()
                if let trailing { Text(trailing).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(hovering ? Color.primary.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
