// Draws Glint's app icon: a prompt and a cursor on graphite, the cursor
// catching the light. The one glowing element is the glint.
// Run: swift scripts/draw-icon.swift <output folder> [light]
import AppKit

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(size: CGFloat, light: Bool) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
    bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = size / 1024
  let small = size <= 32
  func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }

  // macOS icon grid: an 824-point rounded square centred on 1024, with a drop shadow.
  let tileRect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
  let tile = NSBezierPath(roundedRect: tileRect, xRadius: 185 * s, yRadius: 185 * s)
  NSGraphicsContext.saveGraphicsState()
  let drop = NSShadow()
  drop.shadowColor = color(0x000000, light ? 0.25 : 0.45)
  drop.shadowBlurRadius = 24 * s
  drop.shadowOffset = NSSize(width: 0, height: -10 * s)
  drop.set()
  (light ? color(0xF4F3F9) : color(0x16181D)).setFill()
  tile.fill()
  NSGraphicsContext.restoreGraphicsState()
  let ground = light
    ? [color(0xFFFFFF), color(0xF3F2F8), color(0xE4E2EE)]
    : [color(0x2B2E36), color(0x16181D), color(0x0A0B0E)]
  NSGradient(colors: ground)!.draw(in: tile, angle: -90)

  NSGraphicsContext.saveGraphicsState()
  tile.addClip()
  // Soft light from above.
  NSGradient(colors: [color(0xFFFFFF, light ? 0.6 : 0.10), color(0xFFFFFF, 0)])!
    .draw(fromCenter: p(512, 1000), radius: 0, toCenter: p(512, 1000), radius: 700 * s, options: [])

  let ink = light ? color(0x1C1E25) : color(0xF5F4FA)
  let glint = light ? color(0x5B47F0) : color(0x9A8FFF)
  let weight: CGFloat = (small ? 110 : 84) * s

  // The prompt: a chevron.
  let caret = NSBezierPath()
  caret.move(to: p(280, 700))
  caret.line(to: p(470, 512))
  caret.line(to: p(280, 324))
  caret.lineWidth = weight
  caret.lineCapStyle = .round
  caret.lineJoinStyle = .round
  ink.setStroke()
  caret.stroke()

  // The cursor: white fading into violet, with a halo.
  let cursor = NSBezierPath()
  cursor.move(to: p(560, 324))
  cursor.line(to: p(750, 324))
  cursor.lineWidth = weight
  cursor.lineCapStyle = .round
  let tip = p(760, 324)
  NSGradient(colors: [glint.withAlphaComponent(light ? 0.28 : 0.5), glint.withAlphaComponent(0)])!
    .draw(fromCenter: tip, radius: 0, toCenter: tip, radius: (small ? 200 : 250) * s, options: [])
  ink.setStroke()
  cursor.stroke()
  NSGraphicsContext.saveGraphicsState()
  NSBezierPath(
    cgPath: cursor.cgPath.copy(strokingWithWidth: weight, lineCap: .round, lineJoin: .round, miterLimit: 10)
  ).addClip()
  NSGradient(colors: [glint, glint.withAlphaComponent(0)])!
    .draw(fromCenter: tip, radius: 0, toCenter: tip, radius: 250 * s, options: [])
  NSGraphicsContext.restoreGraphicsState()
  NSGraphicsContext.restoreGraphicsState()

  // A hairline rim so the tile holds its edge on any wallpaper.
  if !small {
    let rim = NSBezierPath(roundedRect: tileRect.insetBy(dx: 3 * s, dy: 3 * s), xRadius: 182 * s, yRadius: 182 * s)
    rim.lineWidth = 5 * s
    color(0xFFFFFF, light ? 0.5 : 0.08).setStroke()
    rim.stroke()
  }

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let light = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "light"
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

// Asset catalog sizes for a macOS app icon.
let sizes: [(points: Int, scale: Int)] = [
  (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]
var images: [[String: String]] = []
for (points, scale) in sizes {
  let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
  let data = draw(size: CGFloat(points * scale), light: light).representation(using: .png, properties: [:])!
  try! data.write(to: out.appendingPathComponent(name))
  images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appendingPathComponent("Contents.json"))
print("Wrote \(sizes.count) icon sizes to \(out.path)")
