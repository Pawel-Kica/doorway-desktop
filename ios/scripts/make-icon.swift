// Renders the iPhone app icon from the Mac app's color icon (../Assets/DoorwayColor.png): its tile cropped to a square
// and scaled to a full-bleed 1024 px, opaque, the rounded corners filled with the tile's edge color (iOS rounds the
// corners itself). Run from app/ios: swift scripts/make-icon.swift
import AppKit

let px = 1024
let source = CGImageSourceCreateImageAtIndex(
    CGImageSourceCreateWithURL(URL(fileURLWithPath: "../Assets/DoorwayColor.png") as CFURL, nil)!, 0, nil)!

/// RGBA pixels (premultiplied, row 0 on top) of `image` drawn into a `size` square.
func pixels(_ image: CGImage, size: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: size * size * 4)
    let context = CGContext(data: &data, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return data
}

// The tile is where the (square) source is mostly opaque. Take a centered square inside it, 8 px in from the soft edge,
// so iOS's own corner mask falls entirely on the solid tile.
let size = source.width, full = pixels(source, size: size)
var minX = size, maxX = 0, minY = size, maxY = 0
for y in 0..<size { for x in 0..<size where full[(y * size + x) * 4 + 3] >= 128 {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
} }
let side = min(maxX - minX, maxY - minY) - 16
let tile = CGRect(x: (minX + maxX - side) / 2, y: (minY + maxY - side) / 2, width: side, height: side)
let icon = pixels(source.cropping(to: tile)!, size: px)

// Each pixel that isn't solid (the rounded corners, hidden under iOS's mask) goes over the color of the first solid
// pixel toward the center.
var out = [UInt8](repeating: 255, count: px * px * 4)
for y in 0..<px { for x in 0..<px {
    let i = (y * px + x) * 4
    let dx = Double(px / 2 - x), dy = Double(px / 2 - y), length = max(1, (dx * dx + dy * dy).squareRoot())
    var sx = Double(x), sy = Double(y), solid = i, steps = 0
    while icon[solid + 3] < 250 && steps < px {
        sx += dx / length; sy += dy / length; steps += 1
        solid = (Int(sy) * px + Int(sx)) * 4
    }
    let alpha = Double(icon[i + 3]) / 255, solidAlpha = max(1, Double(icon[solid + 3])) / 255
    for c in 0..<3 {
        let edge = Double(icon[solid + c]) / solidAlpha
        out[i + c] = UInt8(min(255, (Double(icon[i + c]) + (1 - alpha) * edge).rounded()))
    }
} }

// No alpha channel: iOS wants an opaque icon.
let context = CGContext(data: &out, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let destinationURL = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
print(CGImageDestinationFinalize(destination) ? "Wrote \(destinationURL.path)" : "Writing the PNG failed")
