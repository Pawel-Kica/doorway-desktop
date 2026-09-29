import AppKit
import SimpleBlockCore
import SwiftUI

/// Focus tab. Off: the allowlists as toggle chips, a length and Start focus.
/// On: a big countdown and End focus. What's allowed stays editable either way, edits during a focus apply right away.
struct FocusPane: View {
    @ObservedObject var model: AppModel
    /// Length of the next focus, the last one picked.
    @AppStorage("focusMinutes") private var minutes = 120
    @Environment(\.uiScale) private var scale

    /// Focus lengths offered here and in the popover's Start focus menu.
    static let lengths = [(25, "25 min"), (50, "50 min"), (60, "1 h"), (90, "1.5 h"), (120, "2 h"), (180, "3 h"), (240, "4 h")]

    var body: some View {
        // focusLeft rather than focus: a focus that just ran out reads as off until Gatekeeper ends it.
        let on = model.focusLeft > 0
        Pane {
            SectionTitle(title: "Focus") {
                // Negative padding keeps the title row as tall as one without a button.
                IconButton(symbol: "pencil", help: "Edit allowlists") { model.settingsTab = .allowlists }
                    .padding(.vertical, -4 * scale).padding(.trailing, 6 * scale)
            }
            if on, let focus = model.focus { timeLeftCard(until: focus.ends).padding(.bottom, 12 * scale) }
            allowlistsCard.padding(.bottom, 12 * scale)
            if !on {
                Card {
                    CardRow(divider: false) {
                        SettingRow(title: "Length") {
                            HStack(spacing: 6 * scale) {
                                ForEach(Self.lengths, id: \.0) { length, label in
                                    Toggle(isOn: Binding(get: { minutes == length }, set: { if $0 { minutes = length } })) {
                                        Text(label).bezelPadding()
                                    }
                                    .toggleStyle(.button)
                                }
                            }
                        }
                    }
                }
                startButton.padding(.top, 12 * scale)
            }
            if !model.dockGuarded {
                Card {
                    CardRow(divider: false) {
                        SettingRow(title: "Stop Dock clicks", note: "Needs Accessibility, or a Dock click flashes the app for a frame.") {
                            Button { DockGuard.askForAccess() } label: { Text("Allow…").bezelPadding() }
                        }
                    }
                }
                .padding(.top, 12 * scale)
            }
        }
        .navigationTitle("Focus")
    }

    /// The allowlists as toggle chips, then the apps the picked ones hold. A list that's the only thing a running
    /// focus allows can't be unpicked.
    private var allowlistsCard: some View {
        let rules = model.focusRules
        return Card {
            CardRow(divider: false) {
                if rules.allowlists.isEmpty {
                    Text("No allowlists").foregroundStyle(.secondary)
                } else {
                    FlowLayout(spacing: 6 * scale) {
                        ForEach(rules.allowlists) { list in
                            let isOn = rules.picked.contains(list.id)
                            Toggle(isOn: Binding(
                                get: { isOn },
                                set: { if $0 { model.focusRules.picked.insert(list.id) } else { model.focusRules.picked.remove(list.id) } })) {
                                Text(list.name).bezelPadding()
                            }
                            .toggleStyle(.button)
                            .disabled(isOn && !model.canChangeFocus { $0.picked.remove(list.id) })
                            .help(list.entries.isEmpty ? "No apps" : list.entries.map(\.name).joined(separator: ", "))
                        }
                    }
                }
            }
            if !rules.allowed.isEmpty {
                CardRow {
                    FlowLayout(spacing: 14 * scale) {
                        ForEach(rules.allowed) { app in
                            HStack(spacing: 6 * scale) {
                                AppIcon(app: app, size: 20 * scale)
                                Text(app.name).lineLimit(1)
                            }
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The running focus: time left in big digits, when it ends, End focus.
    private func timeLeftCard(until ends: Date) -> some View {
        Card {
            CardRow(divider: false) {
                HStack(spacing: 16 * scale) {
                    VStack(alignment: .leading, spacing: 2 * scale) {
                        HStack(spacing: 8 * scale) {
                            Circle().fill(.green).frame(width: 9 * scale, height: 9 * scale)
                            Text("Focus on")
                        }
                        .scaledFont(15, weight: .semibold)
                        Text(countdown(model.focusLeft))
                            .font(.system(size: 56 * scale, weight: .semibold).monospacedDigit())
                        Text("until \(ends.formatted(date: .omitted, time: .shortened))")
                            .scaledFont(17).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.endFocus() } label: { Text("End focus").bezelPadding() }
                }
                .padding(.vertical, 8 * scale)
            }
        }
    }

    /// Full width, accent colored. Needs something to allow.
    private var startButton: some View {
        Button { model.startFocus(minutes: minutes) } label: {
            HStack(spacing: 10 * scale) {
                Image(systemName: "scope")
                Text("Start focus")
            }
            .scaledFont(17, weight: .semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6 * scale)
        }
        .buttonStyle(.borderedProminent)
        .disabled(model.focusRules.allowed.isEmpty)
    }
}

/// Lays its children out left to right and wraps to a new line when the width runs out.
private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = frames(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: frames.map(\.maxX).max() ?? 0, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(subviews, width: bounds.width)) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            line = max(line, size.height)
        }
        return frames
    }
}
