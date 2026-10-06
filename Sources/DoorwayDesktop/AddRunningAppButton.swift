import AppKit
import DoorwayDesktopCore
import SwiftUI

/// "Add running app" under each allowlist: pops a menu of the regular apps running now that aren't in `skip`, by name.
/// Finder and Doorway Desktop are left out, focus always allows them. An AppKit menu, since a SwiftUI Menu button keeps a small fixed font.
struct AddRunningAppButton: View {
    let skip: [GatedApp]
    let add: (GatedApp) -> Void
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
        var seen = alwaysAllowedInFocus.union(skip.map(\.bundleId))
        var apps: [GatedApp] = []
        for running in NSWorkspace.shared.runningApplications where running.activationPolicy == .regular {
            guard let id = running.bundleIdentifier, let url = running.bundleURL, seen.insert(id).inserted else { continue }
            apps.append(GatedApp(bundleId: id, name: running.localizedName ?? url.deletingPathExtension().lastPathComponent, path: url.path))
        }
        for app in apps.sorted(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) {
            let item = ClosureMenuItem(app.name) { add(app) }
            item.image = NSWorkspace.shared.icon(forFile: app.path)
            item.image?.size = NSSize(width: 16 * scale, height: 16 * scale)
            menu.addItem(item)
        }
        // No action, so it shows disabled.
        if apps.isEmpty { menu.addItem(withTitle: "No other apps running", action: nil, keyEquivalent: "") }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure when picked. Quick session uses it too.
final class ClosureMenuItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(pick), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func pick() { run() }
}
