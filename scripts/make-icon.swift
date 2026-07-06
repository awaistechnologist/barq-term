#!/usr/bin/env swift
import AppKit

// Renders the Barq app icon (a lightning bolt on a gradient) at all required
// sizes and assembles Barq.icns via iconutil.

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return image }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.2237 // macOS squircle-ish corner
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Background gradient — deep indigo to violet (Catppuccin-ish).
    let colors = [
        NSColor(srgbRed: 0.11, green: 0.11, blue: 0.18, alpha: 1).cgColor,
        NSColor(srgbRed: 0.20, green: 0.16, blue: 0.40, alpha: 1).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

    // Lightning bolt path (normalized 0..1, y-up).
    let pts: [(CGFloat, CGFloat)] = [
        (0.56, 0.86), (0.34, 0.48), (0.48, 0.48),
        (0.44, 0.14), (0.66, 0.54), (0.52, 0.54)
    ]
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: pts[0].0 * size, y: pts[0].1 * size))
    for p in pts.dropFirst() {
        bolt.line(to: NSPoint(x: p.0 * size, y: p.1 * size))
    }
    bolt.close()

    // Glow
    ctx.setShadow(offset: .zero, blur: size * 0.04, color: NSColor(srgbRed: 1, green: 0.95, blue: 0.4, alpha: 0.9).cgColor)
    NSColor(srgbRed: 1, green: 0.90, blue: 0.30, alpha: 1).setFill()
    bolt.fill()

    image.unlockFocus()
    return image
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "dist/Barq.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(Int, Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
for (base, scale) in sizes {
    let px = CGFloat(base * scale)
    let image = drawIcon(size: px)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
    try! png.write(to: iconset.appendingPathComponent(name))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "dist/Barq.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ dist/Barq.icns" : "✗ iconutil failed")
