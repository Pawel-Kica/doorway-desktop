import ServiceManagement
import SwiftUI

@main
struct SimpleBlockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    init() {
        // New status items go left of the others, which on a full MacBook menu bar is under the notch. 300 pt from
        // the right edge keeps it in view. ⌘-dragging it saves the new place over this.
        UserDefaults.standard.register(defaults: ["NSStatusItem Preferred Position Item-0": 300])
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let gatekeeper = Gatekeeper(model: .shared)

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerLoginItem()
        AppIconChoice.apply()
        gatekeeper.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.recordQuit()
    }

    /// Opening Simple Block again (Raycast, Spotlight, Finder) brings up Settings. The menu bar icon stays.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsOpener.open?()
        NSApp.activate()
        return false
    }

    /// Adds itself as a login item while it isn't one. Ad-hoc builds may fail, which is fine.
    private func registerLoginItem() {
        guard SMAppService.mainApp.status == .notRegistered else { return }
        do { try SMAppService.mainApp.register() } catch { NSLog("SimpleBlock: login item registration failed: \(error)") }
    }
}

/// SwiftUI opens Settings only through an environment action. The menu bar label, always on screen, hands it over here
/// so the app delegate can open Settings too.
@MainActor
enum SettingsOpener {
    static var open: (() -> Void)?
}
