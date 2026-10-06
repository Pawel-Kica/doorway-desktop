import AppKit

/// App icons to pick in General (`appIcon` in UserDefaults): Doorway's color icon, the Chrome extension's (default,
/// Assets/DoorwayColor.png, copied into the bundle by build.sh) or a white doorway on a #2B2B29 tile. The pick goes on
/// the Dock icon and onto the bundle, so Finder, Raycast and Spotlight show it too. Color is also the bundle's own icon,
/// Assets/AppIcon.icns, made from DoorwayColor.png by scripts/make-icon.sh.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case color, dark

    static let key = "appIcon"
    var id: Self { self }

    var name: String { rawValue.capitalized }

    /// Doorway's color icon, also the one on the prompt and the super lock notice.
    static let colorIcon = Bundle.main.image(forResource: "DoorwayColor")

    /// The icon on the macOS grid: the tile is 80% of the canvas, corners at 22.5% of the tile.
    func image(pixels: Int) -> NSImage {
        if self == .color, let icon = Self.colorIcon { return icon }
        let size = CGFloat(pixels)
        return NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            Self.drawDark(size: size)
            return true
        }
    }

    /// The light through an arch, the door leaf ajar on the left and light on the floor, like the color icon.
    static func drawDark(size: CGFloat) {
        let tile = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.1, dy: size * 0.1)
        let tilePath = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
        NSColor(srgbRed: 0x2B / 255, green: 0x2B / 255, blue: 0x29 / 255, alpha: 1).setFill()
        tilePath.fill()

        let width = size * 0.38, left = (size - width) / 2, bottom = size * 0.30, top = size * 0.78
        let opening = NSBezierPath()
        opening.move(to: NSPoint(x: left, y: bottom))
        opening.line(to: NSPoint(x: left, y: top - width / 2))
        opening.appendArc(withCenter: NSPoint(x: left + width / 2, y: top - width / 2), radius: width / 2,
                          startAngle: 180, endAngle: 0, clockwise: true)
        opening.line(to: NSPoint(x: left + width, y: bottom))
        opening.close()

        NSGraphicsContext.saveGraphicsState()
        tilePath.addClip()
        let floor = NSBezierPath()
        floor.move(to: NSPoint(x: left + width * 0.42, y: bottom))
        floor.line(to: NSPoint(x: left + width, y: bottom))
        floor.line(to: NSPoint(x: left + width + size * 0.13, y: tile.minY))
        floor.line(to: NSPoint(x: left + size * 0.01, y: tile.minY))
        floor.close()
        NSGradient(starting: NSColor.white.withAlphaComponent(0.2), ending: NSColor.white.withAlphaComponent(0))!
            .draw(in: floor, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.setFill()
        opening.fill()
        NSGraphicsContext.saveGraphicsState()
        opening.addClip()
        NSColor(white: 0.36, alpha: 1).setFill()
        NSRect(x: left, y: bottom, width: width * 0.46, height: top - bottom).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    /// The saved pick, Color when none (or an old value).
    static var saved: AppIconChoice {
        UserDefaults.standard.string(forKey: key).flatMap(AppIconChoice.init) ?? .color
    }

    /// Puts `saved` on the Dock icon and the bundle. Color is the bundle's own icon, so it clears the custom one; Dark
    /// goes on as the custom one. Called at launch and on every pick.
    @MainActor
    static func apply() {
        let choice = saved
        let image = choice.image(pixels: 1024)
        NSApp.applicationIconImage = image
        NSWorkspace.shared.setIcon(choice == .color ? nil : image, forFile: Bundle.main.bundlePath)
    }
}
