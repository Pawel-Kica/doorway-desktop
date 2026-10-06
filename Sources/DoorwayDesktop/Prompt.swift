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
    func question(_ name: Text) -> Text {
        switch self {
        case .launch, .switch: Text("Do you really need \(name)?")
        case .expired: Text("Time's up. Do you still need \(name)?")
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

/// The prompt: a see-through panel over the main screen, above all windows and the black backdrop, so the gated app's
/// window can't be seen even when it briefly unhides itself. Doorway's ask page, 1:1. One at a time. Esc is No.
/// The same panel shows the super lock notice.
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

    /// "Do you really need Signal?": Yes asks what you need, then `onOpen` with it (may be empty); Later asks what to
    /// do later, then `onLater` with it; No is `onNo`. `notes` are earlier Later notes, `onCheckOff` gets the index of
    /// one clicked off.
    func show(app: GatedApp, trigger: Trigger, notes: [String], onOpen: @escaping (String) -> Void,
              onLater: @escaping (String) -> Void, onNo: @escaping () -> Void, onCheckOff: @escaping (Int) -> Void) {
        let view = PromptView(app: app, trigger: trigger, notes: notes, onOpen: onOpen, onLater: onLater, onNo: onNo,
                              onCheckOff: onCheckOff)
        open(view, for: app, onEscape: onNo)
    }

    /// "Signal is super locked until 10:00." Esc, OK, ⌘↵ or 6 seconds close it, so it can't stay stuck on screen.
    func showLocked(app: GatedApp, until: String, onClose: @escaping () -> Void) {
        open(LockedView(app: app, until: until, onClose: onClose), for: app, onEscape: onClose, onCommandReturn: onClose)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if self?.bundleId == app.bundleId { onClose() }
        }
    }

    /// The panel covers the main screen with the view centered, so it can change size (Yes, Later, Back).
    private func open(_ view: some View, for app: GatedApp, onEscape: @escaping () -> Void, onCommandReturn: (() -> Void)? = nil) {
        let screen = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let host = NSHostingView(rootView: view.frame(maxWidth: .infinity, maxHeight: .infinity))

        // Keyboard focus comes from bringToFront(), which activates Doorway Desktop; being key alone isn't enough on macOS 14+.
        let panel = PromptPanel(contentRect: screen, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.setFrame(screen, display: false)
        panel.contentView = host
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .modalPanel
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = NSAppearance(named: .darkAqua)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak panel] event in
            guard event.window === panel else { return event }
            if event.keyCode == 53 {
                onEscape()
                return nil
            }
            if let onCommandReturn, [36, 76].contains(event.keyCode), event.modifierFlags.contains(.command) {
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

/// Doorway's ask page, 1:1: "Do you really need Signal?" with Yes / Later / No, then for Yes or Later one line to type
/// in (Return submits, any text or none) with Back. Later notes from earlier show under the question, a click checks
/// one off.
struct PromptView: View {
    enum Step { case question, need, later }

    let app: GatedApp
    let trigger: Trigger
    @State var notes: [String]
    let onOpen: (String) -> Void
    let onLater: (String) -> Void
    let onNo: () -> Void
    let onCheckOff: (Int) -> Void
    @State var step = Step.question
    @State var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        let name = Text(app.name).foregroundStyle(Doorway.light)
        DoorwayPage {
            switch step {
            case .question:
                trigger.question(name)
                if !notes.isEmpty {
                    NoteList(notes: notes) { index in
                        notes.remove(at: index)
                        onCheckOff(index)
                    }
                }
                HStack(spacing: 14) {
                    Button("Yes") { step = .need }.buttonStyle(PillButtonStyle())
                    Button("Later") { step = .later }.buttonStyle(PillButtonStyle())
                    Button("No", action: onNo).buttonStyle(PillButtonStyle(primary: true))
                }
            case .need:
                Text("What do you need in \(name)?")
                input { onOpen(text) }
                HStack(spacing: 14) {
                    Button("Back", action: back).buttonStyle(PillButtonStyle())
                    Button("Open") { onOpen(text) }.buttonStyle(PillButtonStyle(primary: true))
                }
            case .later:
                Text("What do you want to do in \(name) later?")
                input { onLater(text) }
                HStack(spacing: 14) {
                    Button("Back", action: back).buttonStyle(PillButtonStyle())
                    Button("OK") { onLater(text) }.buttonStyle(PillButtonStyle(primary: true))
                }
            }
        }
    }

    private func back() {
        text = ""
        step = .question
    }

    /// Doorway's one-line pill input, focused as soon as it shows.
    private func input(submit: @escaping () -> Void) -> some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 20, weight: .medium))
            .multilineTextAlignment(.center)
            .tint(Doorway.light)
            .focused($focused)
            .onSubmit(submit)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(width: 592)
            .background(.white.opacity(0.08), in: Capsule())
            .onAppear { DispatchQueue.main.async { focused = true } }
    }
}

/// Later notes for the app: "You wanted to:" and a line each, a click on one checks it off.
private struct NoteList: View {
    let notes: [String]
    let checkOff: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("You wanted to:").foregroundStyle(.white.opacity(0.6))
            ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                Button { checkOff(index) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: "circle").foregroundStyle(Doorway.light)
                        Text(note).multilineTextAlignment(.leading)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Done")
            }
        }
        .font(.system(size: 20, weight: .medium))
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(width: 592, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
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
