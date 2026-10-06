import AppKit

/// The black backdrop on every screen, above normal windows, like Doorway's ask and blocked pages. The reason prompt
/// sits on it, and focus puts it up while an app outside focus is on its way out, so neither app's window can be read.
/// Stays up while anyone holds it.
@MainActor
final class Backdrop {
    enum Holder { case prompt, focus }

    private var shields: [NSPanel] = []
    private var holders: Set<Holder> = []
    /// Bumped on every show and release, so a fade that finishes after a new show doesn't take it down.
    private var generation = 0

    /// Builds the windows ahead of time (again if the screens changed), so show() is only an order-front.
    func prepare() {
        guard shields.map(\.frame) != NSScreen.screens.map(\.frame) else { return }
        for shield in shields { shield.close() }
        shields = NSScreen.screens.map { Self.shield(frame: $0.frame) }
        for shield in shields { shield.displayIfNeeded() }
    }

    func isHeld(by holder: Holder) -> Bool { holders.contains(holder) }

    /// Instant, so gating calls it before anything slower.
    func show(for holder: Holder) {
        holders.insert(holder)
        generation += 1
        prepare()
        for shield in shields {
            shield.alphaValue = 1
            shield.orderFrontRegardless()
        }
        // Push it to the screen now, not when this run loop pass ends after the slower work.
        CATransaction.flush()
    }

    /// Takes it down once nobody holds it. `fade` eases it out instead of cutting.
    func release(_ holder: Holder, fade: Bool = false) {
        guard holders.remove(holder) != nil, holders.isEmpty else { return }
        generation += 1
        guard fade else {
            for shield in shields { shield.orderOut(nil) }
            return
        }
        let fading = generation
        let shields = shields
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            for shield in shields { shield.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard self?.generation == fading else { return }
                for shield in shields {
                    shield.orderOut(nil)
                    shield.alphaValue = 1
                }
            }
        }
    }

    /// One screen's backdrop, below the prompt and toasts. Swallows clicks without activating anything.
    private static func shield(frame: NSRect) -> NSPanel {
        let shield = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        shield.setFrame(frame, display: false)
        shield.isOpaque = true
        shield.backgroundColor = .black
        shield.level = .floating
        shield.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        shield.isReleasedWhenClosed = false
        shield.hidesOnDeactivate = false
        // No hides Doorway Desktop to hand focus back; focus may still need the backdrop then.
        shield.canHide = false
        return shield
    }
}
