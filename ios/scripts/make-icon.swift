// Renders the iPhone app icon: the Mac icon's white doorway on a full-bleed #2B2B29 square, 1024 px, opaque (iOS
// rounds the corners itself). Same shapes as Dark in the Mac app's AppIcons.swift, scaled so the square is the Mac
// tile. Run from app/ios: swift scripts/make-icon.swift
import AppKit

let px = 1024
let size = CGFloat(px)
// No alpha channel: iOS wants an opaque icon.
let context = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

NSColor(srgbRed: 0x2B / 255, green: 0x2B / 255, blue: 0x29 / 255, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
// The Mac canvas this square is the 80% tile of.
let canvas = size / 0.8, origin = -canvas * 0.1
let width = canvas * 0.38, left = origin + (canvas - width) / 2, bottom = origin + canvas * 0.30, top = origin + canvas * 0.78
let opening = NSBezierPath()
opening.move(to: NSPoint(x: left, y: bottom))
opening.line(to: NSPoint(x: left, y: top - width / 2))
opening.appendArc(withCenter: NSPoint(x: left + width / 2, y: top - width / 2), radius: width / 2, startAngle: 180, endAngle: 0,
                  clockwise: true)
opening.line(to: NSPoint(x: left + width, y: bottom))
opening.close()
let floor = NSBezierPath()
floor.move(to: NSPoint(x: left + width * 0.42, y: bottom))
floor.line(to: NSPoint(x: left + width, y: bottom))
floor.line(to: NSPoint(x: left + width + canvas * 0.13, y: 0))
floor.line(to: NSPoint(x: left + canvas * 0.01, y: 0))
floor.close()
NSGradient(starting: NSColor.white.withAlphaComponent(0.2), ending: NSColor.white.withAlphaComponent(0))!.draw(in: floor, angle: -90)
NSColor.white.setFill()
opening.fill()
opening.addClip()
NSColor(white: 0.36, alpha: 1).setFill()
NSRect(x: left, y: bottom, width: width * 0.46, height: top - bottom).fill()

let out = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let destination = CGImageDestinationCreateWithURL(out as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
print(CGImageDestinationFinalize(destination) ? "Wrote \(out.path)" : "Writing the PNG failed")
