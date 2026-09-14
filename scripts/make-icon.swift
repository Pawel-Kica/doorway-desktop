// Renders the app icon (white raised hand on an indigo tile) into Assets/AppIcon.icns.
// Run from app/: swift scripts/make-icon.swift
import AppKit

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let size = CGFloat(px)
    // macOS icon grid: the tile is ~80% of the canvas with a continuous-looking corner.
    let tile = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: size * 0.1, dy: size * 0.1)
    let path = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.225, yRadius: tile.width * 0.225)
    NSGradient(starting: NSColor(srgbRed: 0.27, green: 0.35, blue: 0.72, alpha: 1),
               ending: NSColor(srgbRed: 0.12, green: 0.15, blue: 0.34, alpha: 1))!.draw(in: path, angle: -90)
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.4, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let hand = NSImage(systemSymbolName: "hand.raised.fill", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    hand.draw(in: NSRect(x: (size - hand.size.width) / 2, y: (size - hand.size.height) / 2,
                         width: hand.size.width, height: hand.size.height))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try render(points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Assets/AppIcon.icns"]
try FileManager.default.createDirectory(atPath: "Assets", withIntermediateDirectories: true)
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Assets/AppIcon.icns" : "iconutil failed")
