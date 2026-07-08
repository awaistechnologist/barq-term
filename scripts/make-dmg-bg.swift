#!/usr/bin/env swift
import AppKit

// Renders the DMG background (540×380) — dark, on-brand, with a "drag to
// Applications" cue between where the app icon and the Applications alias sit.

let W: CGFloat = 540, H: CGFloat = 380
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); exit(1) }

// Background gradient — Catppuccin-ish ink.
let colors = [
    NSColor(srgbRed: 0.09, green: 0.09, blue: 0.13, alpha: 1).cgColor,
    NSColor(srgbRed: 0.13, green: 0.12, blue: 0.20, alpha: 1).cgColor,
] as CFArray
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: H), end: CGPoint(x: W, y: 0), options: [])

let amber = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.22, alpha: 1)

// Wordmark near the top.
func draw(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat, centerWidth: CGFloat? = nil) {
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    let str = NSAttributedString(string: s, attributes: attrs)
    var px = x
    if let cw = centerWidth { px = x + (cw - str.size().width) / 2 }
    str.draw(at: NSPoint(x: px, y: y))
}
draw("⚡ Barq", NSFont.systemFont(ofSize: 26, weight: .bold), .white, x: 0, y: H - 58, centerWidth: W)
draw("Drag Barq into Applications to install", NSFont.systemFont(ofSize: 12, weight: .regular),
     NSColor(white: 1, alpha: 0.55), x: 0, y: H - 84, centerWidth: W)

// Arrow from the app-icon slot (x≈140) to the Applications slot (x≈400), mid-height.
let y: CGFloat = 175
ctx.setStrokeColor(amber.withAlphaComponent(0.85).cgColor)
ctx.setLineWidth(3)
ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 210, y: y))
ctx.addLine(to: CGPoint(x: 330, y: y))
ctx.strokePath()
// arrowhead
ctx.beginPath()
ctx.move(to: CGPoint(x: 330, y: y))
ctx.addLine(to: CGPoint(x: 316, y: y + 9))
ctx.addLine(to: CGPoint(x: 316, y: y - 9))
ctx.closePath()
ctx.setFillColor(amber.withAlphaComponent(0.85).cgColor)
ctx.fillPath()

image.unlockFocus()
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: "dist/dmg-background.png"))
print("✓ dist/dmg-background.png")
