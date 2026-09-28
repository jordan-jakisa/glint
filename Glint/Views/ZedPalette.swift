import AppKit
import SwiftUI

/// Zed's One Dark and One Light, from `assets/themes/one/one.json` in the Zed
/// repository. Each colour follows the window's appearance, so one value
/// serves AppKit drawing and SwiftUI alike. Used when Style is Zed.
enum ZedPalette {
  static let editor = pair(0x282c33, 0xfafafa)
  static let panel = pair(0x2f343e, 0xebebec)
  static let titleBar = pair(0x3b414d, 0xdcdcdd)
  static let statusBar = pair(0x3b414d, 0xdcdcdd)
  static let tabBar = pair(0x2f343e, 0xebebec)
  static let tabActive = pair(0x282c33, 0xfafafa)
  static let border = pair(0x464b57, 0xc9c9ca)
  static let borderVariant = pair(0x363c46, 0xdfdfe0)
  static let text = pair(0xdce0e5, 0x242529)
  static let textMuted = pair(0xa9afbc, 0x58585a)
  static let textPlaceholder = pair(0x878a98, 0x7e8086)
  static let accent = pair(0x74ade8, 0x5c78e2)
  static let elementHover = pair(0x363c46, 0xdfdfe0)
  static let elementSelected = pair(0x454a56, 0xcacaca)
  static let lineNumber = pair(0x4e5a5f, 0xb4b4bb)
  /// Labels in the git panel.
  static let created = pair(0xa1c181, 0x669f59)
  static let modified = pair(0xdec184, 0xa48819)
  static let deleted = pair(0xd07277, 0xd36151)
  static let renamed = pair(0x74ade8, 0x5c78e2)
  static let conflict = pair(0xdec184, 0xa48819)
  /// Diff hunks.
  static let versionAdded = pair(0x27a657, 0x27a657)
  static let versionDeleted = pair(0xe06c76, 0xe06c76)

  static let terminalBackground = pair(0x282c34, 0xfafafa)
  static let terminalForeground = pair(0xabb2bf, 0x2a2c33)
  /// The 16 ANSI colours: black, red, green, yellow, blue, magenta, cyan,
  /// white, then the bright ones.
  static let ansiDark: [UInt32] = [
    0x282c34, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xabb2bf,
    0x636d83, 0xea858b, 0xaad581, 0xffd885, 0x85c1ff, 0xd398eb, 0x6ed5de, 0xfafafa,
  ]
  static let ansiLight: [UInt32] = [
    0x000000, 0xde3e35, 0x3f953a, 0xd2b67c, 0x2f5af3, 0x950095, 0x0997b3, 0xbbbbbb,
    0x000000, 0xde3e35, 0x3f953a, 0xd2b67c, 0x2f5af3, 0xa00095, 0x0bbcd6, 0xffffff,
  ]

  static func rgb(_ hex: UInt32) -> NSColor {
    NSColor(
      srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
      blue: CGFloat(hex & 0xff) / 255, alpha: 1)
  }

  static func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
  }

  private static func pair(_ dark: UInt32, _ light: UInt32) -> NSColor {
    NSColor(name: nil) { appearance in rgb(isDark(appearance) ? dark : light) }
  }
}
