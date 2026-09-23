import AppKit
import SimpleBlockCore
import SwiftUI

/// The Focus screen: a black window to park on a second display. Opened from the popover, and at launch when it was
/// open at quit. It never shows time left. Ten looks to try (`FocusLook`), picked with ← → or the bar that shows on
/// hover. Clicking it while focus is off starts one for the Focus tab's length.
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

/// What the Focus screen shows. Prototype: ten to pick from, the rest goes once one wins.
enum FocusLook: Int, CaseIterable {
    case word, breathe, candle, stars, lava, oneThing, mantras, orbit, shield, sunrise

    var name: String {
        switch self {
        case .word: "Focus"
        case .breathe: "Breathe"
        case .candle: "Candle"
        case .stars: "Stars"
        case .lava: "Lava"
        case .oneThing: "One thing"
        case .mantras: "Mantras"
        case .orbit: "Orbit"
        case .shield: "Shield"
        case .sunrise: "Sunrise"
        }
    }
}

struct FocusScreenView: View {
    @ObservedObject var model: AppModel
    @AppStorage("focusScreenLook") private var lookIndex = 0
    @AppStorage("focusMinutes") private var minutes = 120
    @State private var showBar = false
    @State private var hover = 0
    @State private var hint: String?

    private var look: FocusLook { FocusLook(rawValue: lookIndex) ?? .word }
    private var on: Bool { model.focus?.isOn(at: model.now) ?? false }

    var body: some View {
        GeometryReader { geo in
            let unit = min(geo.size.width, geo.size.height) / 100
            ZStack {
                // Clicks land here, the looks let them through (except One thing's text field).
                Color.black.contentShape(Rectangle()).onTapGesture(perform: start)
                lookView(unit: unit)
                    .allowsHitTesting(look == .oneThing)
                VStack {
                    Spacer()
                    if let hint {
                        Text(hint).font(.system(size: 2.2 * unit)).foregroundStyle(.white.opacity(0.6))
                    } else if !on {
                        Text("Click to focus · \(durationText(minutes))")
                            .font(.system(size: 2.2 * unit)).foregroundStyle(.white.opacity(0.35))
                    }
                    bar(unit: unit).opacity(showBar ? 1 : 0)
                }
                .padding(.bottom, 3 * unit)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .onContinuousHover { _ in
            withAnimation(.easeOut(duration: 0.2)) { showBar = true }
            hover += 1
        }
        // The bar fades 2.5 s after the mouse stops.
        .task(id: hover) {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.6)) { showBar = false }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
    }

    @ViewBuilder
    private func lookView(unit: CGFloat) -> some View {
        switch look {
        case .word: WordLook(unit: unit)
        case .breathe: BreatheLook(unit: unit)
        case .candle: CandleLook()
        case .stars: StarsLook(unit: unit)
        case .lava: LavaLook(unit: unit)
        case .oneThing: OneThingLook(unit: unit)
        case .mantras: MantrasLook(unit: unit)
        case .orbit: OrbitLook(unit: unit)
        case .shield: ShieldLook(unit: unit, count: hiddenCount)
        case .sunrise: SunriseLook(progress: progress)
        }
    }

    /// "‹ 3/10 Candle ›  Start focus". Shows while the mouse moves.
    private func bar(unit: CGFloat) -> some View {
        HStack(spacing: 2 * unit) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
            Text("\(lookIndex + 1)/\(FocusLook.allCases.count)  \(look.name)").monospacedDigit()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
            Text("·").foregroundStyle(.white.opacity(0.3))
            if on {
                Button("End focus") { model.endFocus() }
            } else {
                Button("Start focus", action: start)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 2 * unit))
        .foregroundStyle(.white.opacity(0.6))
        .padding(.horizontal, 2.4 * unit).padding(.vertical, 1.2 * unit)
        .background(.white.opacity(0.08), in: Capsule())
        .padding(.top, 1.5 * unit)
    }

    private func step(_ by: Int) {
        let count = FocusLook.allCases.count
        lookIndex = ((lookIndex + by) % count + count) % count
    }

    /// Starts focus off a click. With nothing allowed it can't, so it says where to fix that.
    private func start() {
        guard !on else { return }
        model.startFocus(minutes: minutes)
        guard model.focus == nil else { return }
        hint = "Pick apps in Settings → Focus first"
        Task {
            try? await Task.sleep(for: .seconds(3))
            hint = nil
        }
    }

    /// How far through the focus, 0 when off. Only Sunrise uses it, and never as numbers.
    private var progress: Double {
        guard let focus = model.focus, on else { return 0 }
        return model.now.timeIntervalSince(focus.started) / focus.ends.timeIntervalSince(focus.started)
    }

    /// Apps hidden during this focus, or today when off.
    private var hiddenCount: Int {
        let since = on ? model.focus!.started : Calendar.current.startOfDay(for: model.now)
        return model.entries.filter { $0.kind == .hidden && $0.ts >= since }.count
    }
}

// MARK: - Looks

/// 1. The word, breathing slowly.
private struct WordLook: View {
    let unit: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Text("Focus")
                .font(.system(size: 18 * unit, weight: .ultraLight))
                .tracking(2 * unit)
                .foregroundStyle(.white.opacity(0.7 + 0.25 * sin(t * 2 * .pi / 8)))
        }
    }
}

/// 2. Box breathing: 4 s in, hold, out, hold.
private struct BreatheLook: View {
    let unit: CGFloat
    private let phases = ["Breathe in", "Hold", "Breathe out", "Hold"]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 16)
            let phase = Int(t / 4)
            let x = (t - Double(phase) * 4) / 4
            let eased = (1 - cos(x * .pi)) / 2
            let size = [0.35 + 0.65 * eased, 1, 1 - 0.65 * eased, 0.35][phase]
            ZStack {
                Circle().stroke(.white.opacity(0.12), lineWidth: 0.3 * unit).frame(width: 60 * unit)
                Circle()
                    .fill(RadialGradient(colors: [.cyan.opacity(0.35), .indigo.opacity(0.1)], center: .center,
                                         startRadius: 0, endRadius: 30 * unit))
                    .frame(width: 60 * unit * size)
                Text(phases[phase]).font(.system(size: 3 * unit, weight: .light)).foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

/// 3. A candle that never burns down.
private struct CandleLook: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let u = min(size.width, size.height) / 100
                let base = CGPoint(x: size.width / 2, y: size.height * 0.5)
                let flicker = 1 + 0.06 * sin(t * 13) + 0.04 * sin(t * 7.3) + 0.03 * sin(t * 23.1)
                let sway = (sin(t * 1.7) + 0.5 * sin(t * 4.1)) * 0.6 * u
                // Glow
                ctx.fill(Path(ellipseIn: CGRect(x: base.x - 40 * u, y: base.y - 50 * u, width: 80 * u, height: 80 * u)),
                         with: .radialGradient(Gradient(colors: [.orange.opacity(0.18 * flicker), .clear]),
                                               center: CGPoint(x: base.x, y: base.y - 10 * u), startRadius: 0, endRadius: 40 * u))
                // Candle
                ctx.fill(Path(roundedRect: CGRect(x: base.x - 5 * u, y: base.y, width: 10 * u, height: 22 * u), cornerRadius: u),
                         with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(white: 0.35)]),
                                               startPoint: base, endPoint: CGPoint(x: base.x, y: base.y + 22 * u)))
                ctx.stroke(Path { $0.move(to: base); $0.addLine(to: CGPoint(x: base.x, y: base.y - 2 * u)) },
                           with: .color(.black), lineWidth: 0.5 * u)
                // Flame: a teardrop
                let h = 11 * u * flicker, w = 3.2 * u
                let bottom = CGPoint(x: base.x, y: base.y - 1.5 * u)
                let tip = CGPoint(x: base.x + sway, y: bottom.y - h)
                var flame = Path()
                flame.move(to: tip)
                flame.addCurve(to: bottom, control1: CGPoint(x: bottom.x + w * 1.4, y: bottom.y - h * 0.45),
                               control2: CGPoint(x: bottom.x + w, y: bottom.y))
                flame.addCurve(to: tip, control1: CGPoint(x: bottom.x - w, y: bottom.y),
                               control2: CGPoint(x: bottom.x - w * 1.4, y: bottom.y - h * 0.45))
                ctx.fill(flame, with: .linearGradient(Gradient(colors: [.yellow, .orange, Color(red: 1, green: 0.95, blue: 0.8)]),
                                                      startPoint: tip, endPoint: bottom))
                ctx.fill(Path(ellipseIn: CGRect(x: bottom.x - 0.9 * u, y: bottom.y - 3 * u, width: 1.8 * u, height: 3 * u)),
                         with: .color(.blue.opacity(0.5)))
            }
        }
    }
}

/// 4. Flying slowly through stars, the word faint in the middle.
private struct StarsLook: View {
    let unit: CGFloat

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for i in 0..<400 {
                        let x = seeded(i, 1) * 2 - 1, y = seeded(i, 2) * 2 - 1
                        let z = 1 - (seeded(i, 3) + t * 0.02).truncatingRemainder(dividingBy: 1)
                        let p = CGPoint(x: center.x + x / z * size.width * 0.25, y: center.y + y / z * size.width * 0.25)
                        let r = (1 - z) * 2.2 + 0.3
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(.white.opacity(min(1, (1 - z) * 1.5))))
                    }
                }
            }
            Text("Focus").font(.system(size: 6 * unit, weight: .thin)).tracking(unit).foregroundStyle(.white.opacity(0.5))
        }
    }
}

/// 5. A lava lamp: blurred blobs drifting.
private struct LavaLook: View {
    let unit: CGFloat
    private let colors: [Color] = [.indigo, .purple, .teal, .blue, .pink]

    var body: some View {
        ZStack {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate * 0.08
                Canvas { ctx, size in
                    ctx.addFilter(.blur(radius: min(size.width, size.height) * 0.08))
                    for (i, color) in colors.enumerated() {
                        let d = Double(i)
                        let x = size.width * (0.5 + 0.32 * sin(t * (1 + d * 0.23) + d * 1.9))
                        let y = size.height * (0.5 + 0.3 * cos(t * (0.8 + d * 0.17) + d * 2.7))
                        let r = min(size.width, size.height) * (0.16 + 0.05 * sin(t * 2 + d))
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r)),
                                 with: .color(color.opacity(0.55)))
                    }
                }
            }
            Text("Focus").font(.system(size: 9 * unit, weight: .semibold)).foregroundStyle(.black.opacity(0.55))
        }
    }
}

/// 6. The one thing you're on, typed once, shown big.
private struct OneThingLook: View {
    let unit: CGFloat
    @AppStorage("focusScreenOneThing") private var text = ""

    var body: some View {
        VStack(spacing: 3 * unit) {
            Text("THE ONE THING").font(.system(size: 1.8 * unit, weight: .medium)).tracking(0.6 * unit)
                .foregroundStyle(.white.opacity(0.35))
            TextField("", text: $text, prompt: Text("What is it?").foregroundStyle(.white.opacity(0.2)), axis: .vertical)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 7 * unit, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: 80 * unit)
        }
    }
}

/// 7. A short line, a new one every 45 s.
private struct MantrasLook: View {
    let unit: CGFloat
    private let lines = [
        "One thing.", "Stay here.", "You chose this.", "Slow is smooth.", "Nothing else matters right now.",
        "Go deeper.", "The work is the reward.", "Notice. Return.", "Less, but better.", "Be where your hands are.",
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let i = Int(context.date.timeIntervalSinceReferenceDate / 45) % lines.count
            Text(lines[i])
                .font(.system(size: 7 * unit, weight: .light, design: .serif))
                .italic()
                .foregroundStyle(.white.opacity(0.85))
                .id(i)
                .transition(.opacity)
                .animation(.easeInOut(duration: 2), value: i)
        }
    }
}

/// 8. A dot circling a ring, one lap a minute, its trail fading.
private struct OrbitLook: View {
    let unit: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let angle = (t.truncatingRemainder(dividingBy: 60) / 60) * 2 * .pi - .pi / 2
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = 30 * unit
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                           with: .color(.white.opacity(0.08)), lineWidth: 0.25 * unit)
                for k in 0..<60 {
                    let a = angle - Double(k) * 0.012
                    let p = CGPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                    let s = unit * (0.9 - Double(k) * 0.012)
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - s, y: p.y - s, width: 2 * s, height: 2 * s)),
                             with: .color(.white.opacity(0.9 * (1 - Double(k) / 60))))
                }
            }
        }
    }
}

/// 9. How many distractions Simple Block kept away.
private struct ShieldLook: View {
    let unit: CGFloat
    let count: Int

    var body: some View {
        VStack(spacing: 2 * unit) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 8 * unit, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.4))
            Text("\(count)").font(.system(size: 22 * unit, weight: .ultraLight)).monospacedDigit()
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.numericText())
                .animation(.default, value: count)
            Text(count == 1 ? "distraction kept away" : "distractions kept away")
                .font(.system(size: 2.4 * unit)).foregroundStyle(.white.opacity(0.45))
        }
    }
}

/// 10. The sun rises as the focus goes on. No numbers, just light.
private struct SunriseLook: View {
    let progress: Double

    var body: some View {
        Canvas { ctx, size in
            let horizon = size.height * 0.72
            let p = min(1, max(0, progress))
            let r = min(size.width, size.height) * 0.09
            let sun = CGPoint(x: size.width / 2, y: horizon + r * 1.2 - p * (horizon * 0.7))
            ctx.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: horizon)),
                     with: .linearGradient(Gradient(colors: [.black, Color(red: 0.25, green: 0.1, blue: 0.2).opacity(0.3 + 0.7 * p)]),
                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r * 4, y: sun.y - r * 4, width: r * 8, height: r * 8)),
                     with: .radialGradient(Gradient(colors: [.orange.opacity(0.25 + 0.2 * p), .clear]),
                                           center: sun, startRadius: 0, endRadius: r * 4))
            ctx.fill(Path(ellipseIn: CGRect(x: sun.x - r, y: sun.y - r, width: 2 * r, height: 2 * r)),
                     with: .linearGradient(Gradient(colors: [Color(red: 1, green: 0.85, blue: 0.5), .orange]),
                                           startPoint: CGPoint(x: sun.x, y: sun.y - r), endPoint: CGPoint(x: sun.x, y: sun.y + r)))
            ctx.fill(Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)), with: .color(.black))
            ctx.stroke(Path { $0.move(to: CGPoint(x: 0, y: horizon)); $0.addLine(to: CGPoint(x: size.width, y: horizon)) },
                       with: .color(.orange.opacity(0.35)), lineWidth: 1)
        }
    }
}

/// A fixed 0..<1 number per star and axis, so stars keep their places between frames.
private func seeded(_ i: Int, _ salt: Int) -> Double {
    var x = UInt64(i &* 7919 &+ salt &* 104_729) &+ 0x9E37_79B9_7F4A_7C15
    x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
    x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
    x ^= x >> 31
    return Double(x % 10_000) / 10_000
}
