import AppKit

/// App icons to pick in General (`appIcon` in UserDefaults): a white scope on a #2B2B29 tile, like Paweł's Dock, or
/// the old indigo hand. The pick goes on the Dock icon and onto the bundle, so Finder, Raycast and Spotlight show it
/// too. The Scope is also Assets/AppIcon.icns, drawn the same way by scripts/make-icon.swift.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case scope, indigo

    static let key = "appIcon"
    var id: Self { self }

    var name: String { rawValue.capitalized }

    private var symbol: String {
        switch self {
        case .scope: "scope"
        case .indigo: "hand.raised.fill"
        }
    }

    /// Glyph size as a share of the canvas. The thin scope needs more to weigh as much as other Dock icons.
    private var glyphRatio: CGFloat { self == .scope ? 0.52 : 0.36 }

    /// The icon on the macOS grid: the tile is 80% of the canvas, corners at 22.5% of the tile.
    func image(pixels: Int) -> NSImage {
        let size = CGFloat(pixels)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let tile = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.1, dy: size * 0.1)
            let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
            if self == .indigo {
                NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.35, blue: 0.72, alpha: 1),
                           ending: NSColor(srgbRed: 0.12, green: 0.15, blue: 0.34, alpha: 1))!.draw(in: path, angle: -90)
            } else {
                NSColor(srgbRed: 0x2B / 255, green: 0x2B / 255, blue: 0x29 / 255, alpha: 1).setFill()
                path.fill()
            }
            let config = NSImage.SymbolConfiguration(pointSize: size * glyphRatio, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
            guard let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            else { return true }
            let rect = NSRect(x: (size - glyph.size.width) / 2, y: (size - glyph.size.height) / 2,
                              width: glyph.size.width, height: glyph.size.height)
            glyph.draw(in: rect)
            return true
        }
    }

    /// The saved pick, the Scope when none (or a dropped icon).
    static var saved: AppIconChoice {
        UserDefaults.standard.string(forKey: key).flatMap(AppIconChoice.init) ?? .scope
    }

    /// Puts `saved` on the Dock icon and the bundle. The Scope is the bundle's own icon, so it clears the custom one.
    /// Called at launch and on every pick.
    @MainActor
    static func apply() {
        let choice = saved
        let image = choice.image(pixels: 1024)
        NSApp.applicationIconImage = image
        NSWorkspace.shared.setIcon(choice == .scope ? nil : image, forFile: Bundle.main.bundlePath)
    }
}
