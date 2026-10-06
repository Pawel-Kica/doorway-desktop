import AppKit
import DoorwayDesktopCore
import SwiftUI

/// "Quick session" in the Sessions title: pops a menu of blocklists, plus All blocklists when there's more than one,
/// each with a few lengths. Picking a length starts the session. An AppKit menu, like Add running app.
struct QuickSessionButton: View {
    @ObservedObject var model: AppModel
    @Environment(\.uiScale) private var scale
    private let lengths = [(30, "30 min"), (60, "1 h"), (120, "2 h"), (180, "3 h"), (240, "4 h")]

    var body: some View {
        Button(action: showMenu) {
            HStack(spacing: 6 * scale) {
                Text("Quick session")
                Image(systemName: "chevron.down").scaledFont(11, weight: .semibold)
            }
            .bezelPadding()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.font = .systemFont(ofSize: 13 * scale)
        let lists = model.rules.blocklists
        if lists.count > 1 {
            menu.addItem(lengthItem("All blocklists", Set(lists.map(\.id))))
            menu.addItem(.separator())
        }
        for list in lists { menu.addItem(lengthItem(list.name, [list.id])) }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func lengthItem(_ title: String, _ lists: Set<UUID>) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.font = .systemFont(ofSize: 13 * scale)
        for (minutes, label) in lengths {
            submenu.addItem(ClosureMenuItem(label) { model.startQuickSession(lists, minutes: minutes) })
        }
        item.submenu = submenu
        return item
    }
}
