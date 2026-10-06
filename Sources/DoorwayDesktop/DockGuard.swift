import AppKit
import ApplicationServices

/// Stops a click on a Dock icon before the Dock gets it, so an app focus keeps out never comes forward at all. Hiding
/// it afterwards still left a frame or two on screen. Needs Accessibility: an event tap that can drop clicks, and asking
/// the Dock which icon is under the mouse. Cmd-Tab, Raycast and Spotlight still go through hiding and the backdrop.
@MainActor
final class DockGuard {
    /// Whether a click on this bundle ID's icon gets stopped. Asked only while `armed`.
    private let blocks: (String) -> Bool
    /// Called after a click was stopped, with the app's bundle ID and bundle URL.
    private let stopped: (String, URL) -> Void
    /// On during focus. Off, the tap is off too: while it's on, every click on the Mac waits on Doorway Desktop's main thread.
    var armed = false {
        didSet { if armed != oldValue, let tap { CGEvent.tapEnable(tap: tap, enable: armed) } }
    }
    private var tap: CFMachPort?
    private var dock: (pid: pid_t, element: AXUIElement)?
    /// A stopped click's mouse-up is dropped too.
    private var droppingUp = false

    var isRunning: Bool { tap != nil }

    init(blocks: @escaping (String) -> Bool, stopped: @escaping (String, URL) -> Void) {
        self.blocks = blocks
        self.stopped = stopped
    }

    /// Shows the system's Accessibility request, which also puts Doorway Desktop in the list in System Settings.
    static func askForAccess() {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Starts once Accessibility is granted, the tap can't be made before. Cheap enough to call every second.
    func startIfAllowed() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue | 1 << CGEventType.leftMouseUp.rawValue)
        // The source runs on the main run loop, so the callback is on the main thread.
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, info in
            let dockGuard = Unmanaged<DockGuard>.fromOpaque(info!).takeUnretainedValue()
            return MainActor.assumeIsolated { dockGuard.handle(type, event) }
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
        CGEvent.tapEnable(tap: tap, enable: armed)
        self.tap = tap
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS turns off a tap that was slow once. Back on.
            if let tap, armed { CGEvent.tapEnable(tap: tap, enable: true) }
        case .leftMouseDown:
            guard let url = dockApp(at: event.location), let id = Bundle(url: url)?.bundleIdentifier, blocks(id) else { break }
            droppingUp = true
            // After the event is dropped: the toast takes a moment to build and every click waits on this callback.
            DispatchQueue.main.async { self.stopped(id, url) }
            return nil
        case .leftMouseUp where droppingUp:
            droppingUp = false
            return nil
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    /// Bundle URL of the app whose Dock icon is at `point` (top-left screen coordinates, like the event's), nil anywhere
    /// else. Asks the Dock only, never the app under the mouse, which could be hung.
    private func dockApp(at point: CGPoint) -> URL? {
        guard let dock = dockElement() else { return nil }
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(dock, Float(point.x), Float(point.y), &hit) == .success, let hit,
              attribute(hit, kAXSubroleAttribute) as? String == "AXApplicationDockItem" else { return nil }
        return attribute(hit, kAXURLAttribute) as? URL
    }

    /// The Dock's accessibility element, made again after the Dock restarts. A short timeout: the click waits on it.
    private func dockElement() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        if dock?.pid != app.processIdentifier {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(element, 0.25)
            dock = (app.processIdentifier, element)
        }
        return dock?.element
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
}
