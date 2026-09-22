import AppKit
import SimpleBlockCore
import SwiftUI

/// Borderless panels can't take keyboard focus unless told they can.
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class PromptText: ObservableObject {
    @Published var value = ""
}

/// The reason prompt: a glass panel above all windows, over a blurred backdrop on every screen,
/// so the gated app's window can't be seen even when it briefly unhides itself. One at a time.
/// ⌘↵ submits once there are enough words, Esc cancels. The same panel shows the super lock notice.
@MainActor
final class PromptController {
    private var panel: NSPanel?
    private var shields: [NSPanel] = []
    private var keyMonitor: Any?
    /// Bundle ID of the app the prompt is for, nil when closed.
    private(set) var bundleId: String?
    var isShowing: Bool { panel != nil }

    func show(app: GatedApp, trigger: Trigger, nthToday: Int, minutes: Int,
              onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        let text = PromptText()
        let view = PromptView(app: app, trigger: trigger, nthToday: nthToday, minutes: minutes, text: text,
                              onSubmit: { onSubmit(text.value) }, onCancel: onCancel)
        open(view, for: app, onEscape: onCancel) {
            if wordCount(text.value) >= minimumWords { onSubmit(text.value) }
        }
    }

    /// "Signal is locked until 10:00". Esc, OK, ⌘↵ or 6 seconds close it, so it can't stay stuck on screen.
    func showLocked(app: GatedApp, until: String, onClose: @escaping () -> Void) {
        open(LockedView(app: app, until: until, onClose: onClose), for: app, onEscape: onClose, onCommandReturn: onClose)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.bundleId == app.bundleId { onClose() }
        }
    }

    private func open(_ view: some View, for app: GatedApp, onEscape: @escaping () -> Void, onCommandReturn: @escaping () -> Void) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize

        let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 22
        glass.layer?.masksToBounds = true
        host.frame = glass.bounds
        host.autoresizingMask = [.width, .height]
        glass.addSubview(host)

        // Keyboard focus comes from bringToFront(), which activates Simple Block; being key alone isn't enough on macOS 14+.
        let panel = PromptPanel(contentRect: glass.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = glass
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.isMovableByWindowBackground = true
        if let area = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.maxY - area.height * 0.22 - size.height))
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard event.window === panel else { return event }
            if event.keyCode == 53 {
                onEscape()
                return nil
            }
            if [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command) {
                onCommandReturn()
                return nil
            }
            return event
        }
        self.panel = panel
        bundleId = app.bundleId
        bringToFront()
    }

    /// Builds the backdrop windows ahead of time (again if the screens changed), so cover() is only an order-front.
    func prepare() {
        guard shields.map(\.frame) != NSScreen.screens.map(\.frame) else { return }
        for shield in shields { shield.close() }
        shields = NSScreen.screens.map { Self.shield(frame: $0.frame) }
        for shield in shields { shield.displayIfNeeded() }
    }

    /// Puts the backdrop up on every screen. Instant, so gating calls it before anything slower.
    func cover() {
        prepare()
        for shield in shields { shield.orderFrontRegardless() }
        // Push it to the screen now, not when this run loop pass ends after the slower prompt build.
        CATransaction.flush()
    }

    func bringToFront() {
        cover()
        panel?.orderFrontRegardless()
        // A key panel alone doesn't get keystrokes while another app is active, and plain activate() gets refused.
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKey()
    }

    func close() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        panel?.close()
        panel = nil
        for shield in shields { shield.orderOut(nil) }
        bundleId = nil
    }

    /// Blurred, dimmed backdrop for one screen, above normal windows and below the prompt.
    /// The blur keeps a gated app that briefly unhides itself unreadable. Swallows clicks without activating anything.
    private static func shield(frame: NSRect) -> NSPanel {
        let shield = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        shield.setFrame(frame, display: false)
        let blur = NSVisualEffectView()
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.appearance = NSAppearance(named: .darkAqua)
        shield.contentView = blur
        let dim = NSView(frame: blur.bounds)
        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        dim.autoresizingMask = [.width, .height]
        blur.addSubview(dim)
        shield.isOpaque = false
        shield.backgroundColor = .clear
        shield.level = .floating
        shield.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        shield.isReleasedWhenClosed = false
        shield.hidesOnDeactivate = false
        return shield
    }
}

private struct PromptView: View {
    let app: GatedApp
    let trigger: Trigger
    let nthToday: Int
    let minutes: Int
    @ObservedObject var text: PromptText
    let onSubmit: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let words = wordCount(text.value)
        let enough = words >= minimumWords
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                AppIcon(app: app, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text(trigger.question(app.name)).font(.system(size: 20, weight: .semibold))
                    Text(trigger == .expired
                         ? "Your \(minutes) min ran out, so \(app.name) is hidden."
                         : "At least \(minimumWords) words. Saved to your history.")
                        .foregroundStyle(.secondary)
                    Text("\(ordinal(nthToday)) reason for \(app.name) today")
                        .font(.system(size: 13)).foregroundStyle(.tertiary)
                }
            }
            TextEditor(text: $text.value)
                .font(.system(size: 16))
                .scrollContentBackground(.hidden)
                .focused($focused)
                .padding(10)
                .frame(height: 96)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(focused ? Color.accentColor.opacity(0.8) : Color.white.opacity(0.18)))
            HStack(spacing: 12) {
                ProgressView(value: Double(min(words, minimumWords)), total: Double(minimumWords))
                    .frame(width: 100)
                    .tint(enough ? .green : nil)
                Text("\(words) / \(minimumWords) words")
                    .monospacedDigit()
                    .foregroundStyle(enough ? .green : .secondary)
                Spacer()
                Button("Never mind", action: onCancel)
                Button("Open \(app.name)", action: onSubmit)
                    .buttonStyle(.borderedProminent)
                    .disabled(!enough)
            }
            Text("⌘↵ open · esc never mind")
                .font(.system(size: 12)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.system(size: 15))
        .controlSize(.large)
        .padding(28)
        .frame(width: 560)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// Super lock notice: no reason to give, the app has already been quit.
private struct LockedView: View {
    let app: GatedApp
    let until: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                AppIcon(app: app, size: 60)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(app.name) is super locked").font(.system(size: 20, weight: .semibold))
                    Text(until).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer()
                Button("OK", action: onClose).buttonStyle(.borderedProminent)
            }
        }
        .font(.system(size: 15))
        .controlSize(.large)
        .padding(28)
        .frame(width: 560)
    }
}

/// The app's own icon.
struct AppIcon: View {
    let app: GatedApp
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
            .resizable()
            .frame(width: size, height: size)
    }
}
