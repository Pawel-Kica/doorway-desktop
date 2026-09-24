// Renders the app icon (white scope on a #2B2B29 tile, the Scope in AppIcons.swift) into Assets/AppIcon.icns.
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
    NSColor(srgbRed: 0x2B / 255, green: 0x2B / 255, blue: 0x29 / 255, alpha: 1).setFill()
    path.fill()
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.52, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let glyph = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
    glyph.draw(in: NSRect(x: (size - glyph.size.width) / 2, y: (size - glyph.size.height) / 2,
                          width: glyph.size.width, height: glyph.size.height))
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
