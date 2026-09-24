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

        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 18
        glass.layer?.masksToBounds = true
        host.frame = glass.bounds
        glass.addSubview(host)

        let panel = NSPanel(contentRect: glass.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = glass
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
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(subtitle).font(.system(size: 14)).foregroundStyle(.secondary).monospacedDigit()
            }
            .lineLimit(1)
        }
        .padding(.leading, 16).padding(.trailing, 24).padding(.vertical, 14)
    }
}
