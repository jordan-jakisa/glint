// Draws the README banner, dark and light: the icon, the name, and the tagline.
// Run from the repository root: swift scripts/draw-banner.swift
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

let icon = NSImage(contentsOfFile: "docs/assets/icon.png")!
let width: CGFloat = 1600, height: CGFloat = 600

for dark in [true, false] {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
    bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

  let card = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height), xRadius: 36, yRadius: 36)
  NSGradient(colors: dark ? [color(0x1A1C22), color(0x0B0C0F)] : [color(0xFFFFFF), color(0xEFEEF6)])!
    .draw(in: card, angle: -90)
  card.addClip()
  // The glint: a soft violet light behind the icon.
  let glow = NSPoint(x: 400, y: 300)
  let violet = dark ? color(0x9A8FFF) : color(0x5B47F0)
  NSGradient(colors: [violet.withAlphaComponent(dark ? 0.22 : 0.12), violet.withAlphaComponent(0)])!
    .draw(fromCenter: glow, radius: 0, toCenter: glow, radius: 420, options: [])

  icon.draw(in: NSRect(x: 150, y: 80, width: 440, height: 440))

  let ink = dark ? color(0xF5F4FA) : color(0x16181D)
  let soft = dark ? color(0xA9A8B6) : color(0x5C5B6A)
  NSAttributedString(
    string: "Glint",
    attributes: [.font: NSFont.systemFont(ofSize: 150, weight: .bold), .foregroundColor: ink, .kern: -4]
  ).draw(at: NSPoint(x: 640, y: 280))
  NSAttributedString(
    string: "Every change, at a glance.",
    attributes: [.font: NSFont.systemFont(ofSize: 46, weight: .medium), .foregroundColor: ink]
  ).draw(at: NSPoint(x: 648, y: 212))
  NSAttributedString(
    string: "A fast, native git panel for the Mac",
    attributes: [.font: NSFont.systemFont(ofSize: 32, weight: .regular), .foregroundColor: soft]
  ).draw(at: NSPoint(x: 648, y: 158))

  NSGraphicsContext.restoreGraphicsState()
  try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "docs/assets/banner-\(dark ? "dark" : "light").png"))
}
print("Wrote docs/assets/banner-dark.png and banner-light.png")
