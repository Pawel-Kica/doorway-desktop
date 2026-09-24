import AppKit
import SwiftUI

/// The Focus screen: a black window with the word "Focus", to park on a second display. Opened from the popover, by
/// opening Simple Block again, and at launch when it was open at quit. It never shows time left. Clicking it while
/// focus is off starts one for the Focus tab's length.
@MainActor
final class FocusScreen: NSObject, NSWindowDelegate {
    static let shared = FocusScreen()
    /// Whether it was open when Simple Block quit.
    static let openKey = "focusScreenOpen"
    private var window: NSWindow?

    /// Brings the window up where it was last. `activate` false at launch, so it doesn't take the keyboard.
    func show(activate: Bool = true) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 600),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Focus"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
            window.isReleasedWhenClosed = false
            // Gatekeeper hides Simple Block after a prompt to hand focus back. This window stays.
            window.canHide = false
            window.collectionBehavior = [.fullScreenPrimary]
            window.contentView = NSHostingView(rootView: FocusScreenView(model: .shared))
            window.delegate = self
            if !window.setFrameUsingName("FocusScreen") { window.center() }
            window.setFrameAutosaveName("FocusScreen")
            self.window = window
        }
        if activate {
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
        } else {
            window?.orderFront(nil)
        }
        UserDefaults.standard.set(true, forKey: Self.openKey)
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: Self.openKey)
    }
}

/// "Focus" in thin white type on black. Nothing moves.
struct FocusScreenView: View {
    @ObservedObject var model: AppModel
    @AppStorage("focusMinutes") private var minutes = 120
    @State private var hint: String?

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 100
            ZStack {
                Color.black
                Text("Focus")
                    .font(.system(size: 18 * unit, weight: .ultraLight))
                    .tracking(2 * unit)
                    .foregroundStyle(.white.opacity(0.85))
                if let hint {
                    Text(hint).font(.system(size: 2.2 * unit)).foregroundStyle(.white.opacity(0.6))
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 5 * unit)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: start)
        }
        .ignoresSafeArea()
    }

    /// Starts focus off a click. With nothing allowed it can't, so it says where to fix that.
    private func start() {
        guard model.focusLeft == 0 else { return }
        model.startFocus(minutes: minutes)
        guard model.focus == nil else { return }
        hint = "Pick apps in Settings → Focus first"
        Task {
            try? await Task.sleep(for: .seconds(3))
            hint = nil
        }
    }
}
