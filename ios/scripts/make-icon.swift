// Renders the iPhone app icon: the Mac icon's white scope on a full-bleed #2B2B29 square, 1024 px, opaque (iOS rounds
// the corners itself). Run from app/ios: swift scripts/make-icon.swift
import AppKit

let px = 1024
let size = CGFloat(px)
// No alpha channel: iOS wants an opaque icon.
let context = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

NSColor(srgbRed: 0x2B / 255, green: 0x2B / 255, blue: 0x29 / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
// Same glyph-to-tile ratio as the Mac icon (0.52 of an 80% tile).
let config = NSImage.SymbolConfiguration(pointSize: size * 0.65, weight: .medium)
    .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
let glyph = NSImage(systemSymbolName: "scope", accessibilityDescription: nil)!.withSymbolConfiguration(config)!
glyph.draw(in: NSRect(x: (size - glyph.size.width) / 2, y: (size - glyph.size.height) / 2,
                      width: glyph.size.width, height: glyph.size.height))

let out = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
print(CGImageDestinationFinalize(destination) ? "Wrote \(out.path)" : "Writing the PNG failed")
