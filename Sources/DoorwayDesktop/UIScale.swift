import AppKit
import SwiftUI

/// How big the UI draws, 1.0 to 2.0 (100% to 200%). Stored as `uiScale` in UserDefaults, read with
/// `@AppStorage(UIScale.key) var scale = UIScale.standard` at the top of a window and passed down as `\.uiScale`.
/// Views multiply font sizes (`scaledFont`), icon sizes and paddings by it.
enum UIScale {
    static let key = "uiScale"
    static let standard = 1.25
    static let range = 1.0...2.0
    /// One ⌘+ or ⌘− step, and the choices in General.
    static let step = 0.25
    static let choices = [1.0, 1.25, 1.5, 1.75, 2.0]

    /// `scale` moved by `steps`, kept in range.
    static func stepped(_ scale: Double, by steps: Int) -> Double {
        min(range.upperBound, max(range.lowerBound, scale + Double(steps) * step))
    }

    /// Large controls, extra large from 150% up.
    static func controlSize(_ scale: Double) -> ControlSize {
        scale < 1.5 ? .large : .extraLarge
    }

    /// `width` x `height` points at 100%, scaled, but never more than 90% of the main screen.
    static func size(_ width: CGFloat, _ height: CGFloat, scale: Double) -> CGSize {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: CGFloat.infinity, height: .infinity)
        return CGSize(width: min(width * scale, screen.width * 0.9), height: min(height * scale, screen.height * 0.9))
    }
}

extension NSWindow {
    /// Moves the window back inside the visible part of its screen. Too big to fit, its top left corner stays on screen.
    func keepOnScreen() {
        guard let visible = screen?.visibleFrame else { return }
        var frame = frame
        frame.origin.x = max(visible.minX, min(frame.minX, visible.maxX - frame.width))
        frame.origin.y = min(visible.maxY - frame.height, max(frame.minY, visible.minY))
        if frame != self.frame { setFrameOrigin(frame.origin) }
    }
}

private struct UIScaleKey: EnvironmentKey {
    static let defaultValue = UIScale.standard
}

extension EnvironmentValues {
    var uiScale: Double {
        get { self[UIScaleKey.self] }
        set { self[UIScaleKey.self] = newValue }
    }
}

extension View {
    /// System font of `size` points at 100%, times `\.uiScale`.
    func scaledFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(ScaledFont(size: size, weight: weight))
    }
}

extension View {
    /// Room around a bordered button's or toggle chip's label. Past 100% the font outgrows the control size and
    /// the bezel hugs the text, so this adds padding that grows with `\.uiScale` (none at 100%).
    func bezelPadding() -> some View {
        modifier(BezelPadding())
    }
}

private struct BezelPadding: ViewModifier {
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View {
        content.padding(.horizontal, 4 * (scale - 1)).padding(.vertical, 6 * (scale - 1))
    }
}

private struct ScaledFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight
    @Environment(\.uiScale) private var scale

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight))
    }
}

extension ToggleStyle where Self == ScaledSwitchStyle {
    /// A switch that grows with `\.uiScale`. The AppKit one stays the same size whatever the control size.
    static var scaledSwitch: ScaledSwitchStyle { ScaledSwitchStyle() }
}

struct ScaledSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ScaledSwitch(configuration: configuration)
    }
}

/// 36 x 20 points at 100%, accent colored when on, like the system switch.
private struct ScaledSwitch: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.uiScale) private var scale
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 0.5 * scale, y: 0.5 * scale)
                        .padding(1.5 * scale)
                }
                .frame(width: 36 * scale, height: 20 * scale)
                .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}
