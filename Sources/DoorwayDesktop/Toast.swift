import AppKit
import SwiftUI

/// A short notice at the top center of the screen the mouse is on, e.g. "T3 Code is hidden while you focus".
/// Never takes focus or clicks, hides itself after 2.5 s, and a new one replaces the current one.
@MainActor
final class ToastController {
    private var panel: NSPanel?

    func show(icon: NSImage, title: String, subtitle: String) {
        panel?.close()
        let host = NSHostingView(rootView: ToastView(icon: icon, title: title, subtitle: subtitle))
        let size = host.fittingSize

        // Black like Doorway's pages, with a faint edge so it still reads on the black backdrop.
        let card = NSView(frame: NSRect(origin: .zero, size: size))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.black.cgColor
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.layer?.borderWidth = 1
        card.layer?.cornerRadius = 18
        card.layer?.masksToBounds = true
        host.frame = card.bounds
        card.addSubview(host)

        let panel = NSPanel(contentRect: card.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = card
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Above the backdrop, which focus puts up again on every attempt.
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        let mouse = NSEvent.mouseLocation
        if let area = (NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 28))
        }
        panel.orderFrontRegardless()
        self.panel = panel

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak panel] in
            guard let panel, self?.panel === panel else { return }
            panel.close()
            self?.panel = nil
        }
    }
}

private struct ToastView: View {
    let icon: NSImage
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: icon).resizable().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.white.opacity(0.6)).monospacedDigit()
            }
            .lineLimit(1)
        }
        .padding(.leading, 16).padding(.trailing, 24).padding(.vertical, 14)
    }
}
