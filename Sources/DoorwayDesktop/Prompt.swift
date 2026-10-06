import AppKit
import DoorwayDesktopCore
import SwiftUI

/// What brought the prompt up.
enum Trigger {
    case launch, `switch`, expired

    var kind: LogKind {
        switch self {
        case .launch: .launch
        case .switch: .switch
        case .expired: .expired
        }
    }

    /// The question, the app's name in Doorway's warm light.
    func question(_ app: String) -> Text {
        let name = Text(app).foregroundStyle(Doorway.light)
        return switch self {
        case .launch: Text("Why are you opening \(name)?")
        case .switch: Text("Why are you switching to \(name)?")
        case .expired: Text("Time's up. Why stay in \(name)?")
        }
    }
}

/// The look of Doorway's ask and blocked pages in the Chrome extension: white on black, the color icon, the site (here
/// the app) in the icon's warm light, pill buttons.
enum Doorway {
    static let light = Color(red: 0xFD / 255, green: 0xE9 / 255, blue: 0xB5 / 255)
    static let blue = Color(red: 44 / 255, green: 59 / 255, blue: 109 / 255)
    static let textSize: CGFloat = 34
    static let iconSize: CGFloat = 134

    static var icon: NSImage { AppIconChoice.colorIcon ?? NSApp.applicationIconImage }
}

/// Doorway's pill button: white 12% or, for the main one, Doorway blue.
struct PillButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        PillLabel(label: configuration.label, primary: primary, pressed: configuration.isPressed)
    }

    private struct PillLabel<Label: View>: View {
        let label: Label
        let primary: Bool
        let pressed: Bool
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            label
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white)
                .frame(minWidth: 88)
                .padding(.vertical, 14)
                .padding(.horizontal, 28)
                .background(primary ? Doorway.blue : Color.white.opacity(pressed ? 0.2 : 0.12), in: Capsule())
                .brightness(primary && pressed ? 0.06 : 0)
                .opacity(enabled ? 1 : 0.4)
                .contentShape(Capsule())
        }
    }
}

/// Borderless panels can't take keyboard focus unless told they can.
private final class PromptPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class PromptText: ObservableObject {
    @Published var value = ""
}

/// The reason prompt: a see-through panel above all windows, centered on the black backdrop, so the gated app's window
/// can't be seen even when it briefly unhides itself. Looks like Doorway's ask page. One at a time.
/// ⌘↵ submits once there are enough words, Esc cancels. The same panel shows the super lock notice.
@MainActor
final class PromptController {
    private let backdrop: Backdrop
    private var panel: NSPanel?
    private var keyMonitor: Any?
    /// Bundle ID of the app the prompt is for, nil when closed.
    private(set) var bundleId: String?
    var isShowing: Bool { panel != nil }

    init(backdrop: Backdrop) {
        self.backdrop = backdrop
    }

    func show(app: GatedApp, trigger: Trigger, nthToday: Int, minutes: Int,
              onSubmit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        let text = PromptText()
        let view = PromptView(app: app, trigger: trigger, nthToday: nthToday, minutes: minutes, text: text,
                              onSubmit: { onSubmit(text.value) }, onCancel: onCancel)
        open(view, for: app, onEscape: onCancel) {
            if wordCount(text.value) >= minimumWords { onSubmit(text.value) }
        }
    }

    /// "Signal is super locked until 10:00." Esc, OK, ⌘↵ or 6 seconds close it, so it can't stay stuck on screen.
    func showLocked(app: GatedApp, until: String, onClose: @escaping () -> Void) {
        open(LockedView(app: app, until: until, onClose: onClose), for: app, onEscape: onClose, onCommandReturn: onClose)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.bundleId == app.bundleId { onClose() }
        }
    }

    private func open(_ view: some View, for app: GatedApp, onEscape: @escaping () -> Void, onCommandReturn: @escaping () -> Void) {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize

        // Keyboard focus comes from bringToFront(), which activates Doorway Desktop; being key alone isn't enough on macOS 14+.
        let panel = PromptPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.contentView = host
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)
        if let screen = NSScreen.main?.frame {
            panel.setFrameOrigin(NSPoint(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2))
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

    /// Puts the backdrop up on every screen. Instant, so gating calls it before anything slower.
    func cover() {
        backdrop.show(for: .prompt)
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
        backdrop.release(.prompt)
        bundleId = nil
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
        DoorwayPage {
            VStack(spacing: 12) {
                Text("\(trigger.question(app.name)) (\(ordinal(nthToday)))")
                if trigger == .expired {
                    Text("Your \(minutes) min ran out, so \(app.name) is hidden.")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            VStack(spacing: 12) {
                TextEditor(text: $text.value)
                    .font(.system(size: 20, weight: .medium))
                    .multilineTextAlignment(.center)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($focused)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(width: 592, height: 80)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 40))
                Text("\(words) / \(minimumWords) words")
                    .font(.system(size: 16))
                    .monospacedDigit()
                    .foregroundStyle(enough ? Doorway.light : .white.opacity(0.5))
            }
            HStack(spacing: 14) {
                Button("Never mind", action: onCancel).buttonStyle(PillButtonStyle())
                Button("Open \(app.name)", action: onSubmit)
                    .buttonStyle(PillButtonStyle(primary: true))
                    .disabled(!enough)
            }
        }
        .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// Super lock notice: no reason to give, the app has already been quit. Looks like Doorway's blocked page.
private struct LockedView: View {
    let app: GatedApp
    /// "until 10:00", "all day, every day".
    let until: String
    let onClose: () -> Void

    var body: some View {
        DoorwayPage {
            Text("\(Text(app.name).foregroundStyle(Doorway.light)) is super locked \(until).")
            Button("OK", action: onClose).buttonStyle(PillButtonStyle(primary: true))
        }
    }
}

/// Doorway's ask and blocked page layout: the color icon, then the content, centered, white text at Doorway's size.
private struct DoorwayPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 48) {
            Image(nsImage: Doorway.icon)
                .resizable()
                .frame(width: Doorway.iconSize, height: Doorway.iconSize)
            VStack(spacing: 32) { content }
        }
        .font(.system(size: Doorway.textSize, weight: .medium))
        .foregroundStyle(.white)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 900)
        .padding(.vertical, 40)
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
