import AppKit
import SimpleBlockCore
import SwiftUI

/// Focus tab. Off: the allowlists as toggle chips, apps allowed on their own as chips, a length and Start focus.
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
            if on, let focus = model.focus { timeLeftCard(until: focus.ends).padding(.bottom, 12 * scale) }
            SectionTitle(title: "Allowlists") {
                // Negative padding keeps the title row as tall as one without a button.
                IconButton(symbol: "pencil", help: "Edit allowlists") { model.settingsTab = .allowlists }
                    .padding(.vertical, -4 * scale).padding(.trailing, 6 * scale)
            }
            allowlistsCard.padding(.bottom, 12 * scale)
            SectionTitle(title: "Also allow") {}
            Card {
                CardRow(divider: false) {
                    if model.focusRules.apps.isEmpty {
                        Text("No apps").foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8 * scale) {
                            ForEach(model.focusRules.apps) { app in
                                AppChip(app: app, removable: model.canChangeFocus { $0.apps.removeAll { $0.id == app.id } }) {
                                    model.removeFocusApp(app.bundleId)
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10 * scale) {
                Spacer()
                AddRunningAppButton(model: model)
                Button { model.addFocusApps() } label: { Text("Add app…").bezelPadding() }
            }
            .padding(.bottom, 12 * scale)
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
            Text("Everything else stays open, just hidden. Finder and Simple Block always work.")
                .noteFont().foregroundStyle(.secondary).padding(.leading, 4 * scale)
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
            if !rules.listed.isEmpty {
                CardRow {
                    FlowLayout(spacing: 14 * scale) {
                        ForEach(rules.listed) { app in
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

/// An allowed app as a chip: icon, name and a remove x, disabled on the last app while focus is on.
private struct AppChip: View {
    let app: GatedApp
    let removable: Bool
    let remove: () -> Void
    @Environment(\.uiScale) private var scale

    var body: some View {
        HStack(spacing: 8 * scale) {
            AppIcon(app: app, size: 24 * scale)
            Text(app.name).lineLimit(1)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill").scaledFont(14)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(!removable)
            .help(removable ? "Remove \(app.name)" : "Focus needs at least one app")
            .accessibilityLabel("Remove \(app.name)")
        }
        .padding(.leading, 7 * scale).padding(.trailing, 9 * scale).padding(.vertical, 5 * scale)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
    }
}

/// "Add running app": pops a menu of the regular apps running now that focus doesn't allow yet, by name. Finder and
/// Simple Block are left out, they always work. An AppKit menu, since a SwiftUI Menu button keeps a small fixed font.
private struct AddRunningAppButton: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiScale) private var scale

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6 * scale) {
                Text("Add running app")
                Image(systemName: "chevron.down").scaledFont(11, weight: .semibold)
            }
            .bezelPadding()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.font = .systemFont(ofSize: 13 * scale)
        var seen = alwaysAllowedInFocus.union(model.focusRules.allowed.map(\.bundleId))
        var apps: [GatedApp] = []
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            guard let id = running.bundleIdentifier, let url = running.bundleURL, seen.insert(id).inserted else { continue }
            apps.append(GatedApp(bundleId: id, name: running.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path))
        }
        for app in apps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let item = ClosureMenuItem(app.name) { model.addFocusApp(app) }
            item.image = NSWorkspace.shared.icon(forFile: app.path)
            item.image?.size = NSSize(width: 16 * scale, height: 16 * scale)
            menu.addItem(item)
        }
        // No action, so it shows disabled.
        if apps.isEmpty { menu.addItem(withTitle: "No other apps running", action: nil, keyEquivalent: "") }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure when picked.
private final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(pick), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func pick() { run() }
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
