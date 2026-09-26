// Draws Adit's app icon: a timber-framed adit (a mine's horizontal entrance)
// cut into dark rock, with the seam inside drawn as a diff's added and
// removed lines. Run: swift scripts/draw-icon.swift <output folder>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(size: CGFloat) -> NSBitmapImageRep {
  let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
    bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let s = size / 1024
  func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x * s, y: y * s, width: w * s, height: h * s)
  }

  // macOS icon grid: an 824-point rounded square centred on 1024.
  let plate = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
  NSGradient(colors: [color(0x3A4252), color(0x1B2029)])!.draw(in: plate, angle: -90)

  plate.addClip()
  // Rock strata: faint diagonal bands.
  color(0xFFFFFF, 0.035).setFill()
  for i in 0..<6 {
    let band = NSBezierPath()
    let y = CGFloat(180 + i * 130)
    band.move(to: NSPoint(x: 60 * s, y: y * s))
    band.line(to: NSPoint(x: 980 * s, y: (y + 90) * s))
    band.line(to: NSPoint(x: 980 * s, y: (y + 130) * s))
    band.line(to: NSPoint(x: 60 * s, y: (y + 40) * s))
    band.close()
    band.fill()
  }

  // The tunnel mouth: an opening with a rounded top.
  let mouth = NSBezierPath(roundedRect: r(292, 150, 440, 560), xRadius: 150 * s, yRadius: 150 * s)
  let floor = NSBezierPath(rect: r(292, 150, 440, 200))
  mouth.append(floor)
  NSGradient(colors: [color(0x07090D), color(0x131820)])!.draw(in: mouth, angle: 90)

  // The seam inside: diff lines receding into the dark.
  let lines: [(y: CGFloat, width: CGFloat, hex: UInt32, alpha: CGFloat)] = [
    (520, 250, 0x3FB950, 1.0), (455, 190, 0xF85149, 0.95), (390, 280, 0x3FB950, 0.9),
    (325, 150, 0x3FB950, 0.75), (260, 220, 0xF85149, 0.6),
  ]
  for line in lines {
    let bar = NSBezierPath(roundedRect: r(512 - line.width / 2, line.y, line.width, 34), xRadius: 17 * s, yRadius: 17 * s)
    color(line.hex, line.alpha).setFill()
    bar.fill()
  }

  // Timber frame: two posts and a lintel, amber, the accent colour.
  let timber = color(0xD08A2E)
  let timberDark = color(0x9A5E17)
  for x in [262.0, 712.0] as [CGFloat] {
    NSGradient(colors: [timber, timberDark])!.draw(in: NSBezierPath(roundedRect: r(x, 150, 50, 470), xRadius: 8 * s, yRadius: 8 * s), angle: 0)
  }
  NSGradient(colors: [timber, timberDark])!.draw(
    in: NSBezierPath(roundedRect: r(232, 610, 560, 64), xRadius: 10 * s, yRadius: 10 * s), angle: -90)

  // Ground line.
  color(0x0B0E13, 0.9).setFill()
  NSBezierPath(rect: r(100, 100, 824, 50)).fill()

  NSGraphicsContext.restoreGraphicsState()
  return rep
}

// Asset catalog sizes for a macOS app icon.
let sizes: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var images: [[String: String]] = []
for (points, scale) in sizes {
  let pixels = CGFloat(points * scale)
  let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
  let data = draw(size: pixels).representation(using: .png, properties: [:])!
  try! data.write(to: out.appendingPathComponent(name))
  images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try! json.write(to: out.appendingPathComponent("Contents.json"))
print("Wrote \(sizes.count) icon sizes to \(out.path)")
