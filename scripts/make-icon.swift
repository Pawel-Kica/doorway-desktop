// Renders the app icon (white doorway on a #2B2B29 tile, Dark in AppIcons.swift, drawn the same way) into
// Assets/AppIcon.icns. Run from app/: swift scripts/make-icon.swift
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
