import ServiceManagement
import SwiftUI

@main
struct DoorwayDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
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
        openSettings()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.recordQuit()
    }

    /// Clicking the Dock icon or opening Doorway Desktop again (Raycast, Spotlight, Finder) brings up Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        NSApp.activate()
        return false
    }

    /// Opens the Settings window, the app's only one. SwiftUI gives that action to views only, so this picks
    /// Settings… (⌘,) in the app menu.
    private func openSettings() {
        guard let menu = NSApp.mainMenu?.items.first?.submenu,
              let index = menu.items.firstIndex(where: { $0.keyEquivalent == "," }) else { return }
        menu.performActionForItem(at: index)
    }

    /// Adds itself as a login item while it isn't one. Ad-hoc builds may fail, which is fine.
    private func registerLoginItem() {
        guard SMAppService.mainApp.status == .notRegistered else { return }
        do { try SMAppService.mainApp.register() } catch { NSLog("DoorwayDesktop: login item registration failed: \(error)") }
    }
}
