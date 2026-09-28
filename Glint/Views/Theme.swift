import AppKit
import SwiftUI

/// How Glint looks: light or dark, the accent, the diff colours, and whether
/// its toolbar uses Liquid Glass. Set in Settings, Appearance; saved between launches.
@MainActor
@Observable
final class Theme {
  static let shared = Theme()
  static let didChange = Notification.Name("GlintThemeDidChange")

  enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
      switch self {
      case .system: "System"
      case .light: "Light"
      case .dark: "Dark"
      }
    }
  }

  enum Accent: String, CaseIterable, Identifiable {
    case system, violet, blue, green, orange, pink, graphite
    var id: String { rawValue }
    var title: String { self == .system ? "System" : rawValue.capitalized }
    var color: NSColor {
      switch self {
      case .system: .controlAccentColor
      case .violet: NSColor(named: "AccentColor") ?? .systemPurple
      case .blue: .systemBlue
      case .green: .systemGreen
      case .orange: .systemOrange
      case .pink: .systemPink
      case .graphite: .systemGray
      }
    }
  }

  /// Standard has a toolbar and a branch bar; Minimal, like Zed, has no
  /// toolbar, one status line along the bottom, a one-line commit box until
  /// you use it, and tighter lists.
  enum Interface: String, CaseIterable, Identifiable {
    case standard, minimal
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard" : "Minimal" }
  }

  /// How far secondary and tertiary text fade. macOS's own levels are faint
  /// on a light background, so even Standard sits above them.
  enum Contrast: String, CaseIterable, Identifiable {
    case standard, high
    var id: String { rawValue }
    var title: String { self == .standard ? "Standard" : "High" }
    var secondary: Double { self == .standard ? 0.72 : 0.88 }
    var tertiary: Double { self == .standard ? 0.5 : 0.7 }
  }

  /// Green and red, or blue and orange, which stay apart for red-green
  /// colour blindness (the most common kind).
  enum DiffColors: String, CaseIterable, Identifiable {
    case greenRed, blueOrange
    var id: String { rawValue }
    var title: String { self == .greenRed ? "Green and red" : "Blue and orange" }
  }

  /// Bumped on every change, for views that draw colours themselves.
  private(set) var version = 0
  private(set) var appearance: Appearance
  private(set) var accent: Accent
  private(set) var diffColors: DiffColors
  private(set) var contrast: Contrast
  private(set) var interface: Interface
  var isMinimal: Bool { interface == .minimal }
  /// Flat controls: Minimal, or Liquid Glass turned off.
  var isFlat: Bool { isMinimal || !usesLiquidGlass }
  /// Style Zed: Liquid Glass off, and Zed's One Dark and One Light colours
  /// throughout.
  var isZed: Bool { !usesLiquidGlass }
  /// Off, toolbar items drop their glass capsules and sit flat. macOS has
  /// no public switch for the rest (the sidebar, menus), and the
  /// undocumented per-app one did nothing on macOS 27, so this covers what
  /// Glint draws itself.
  private(set) var usesLiquidGlass: Bool
  private let defaults = UserDefaults.standard

  private init() {
    appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
    accent = Accent(rawValue: defaults.string(forKey: "accent") ?? "") ?? .system
    diffColors = DiffColors(rawValue: defaults.string(forKey: "diffColors") ?? "") ?? .greenRed
    contrast = Contrast(rawValue: defaults.string(forKey: "contrast") ?? "") ?? .standard
    interface = Interface(rawValue: defaults.string(forKey: "interface") ?? "") ?? .standard
    usesLiquidGlass = !UserDefaults.standard.bool(forKey: "flatToolbar")
  }

  // MARK: Colours

  var accentColor: NSColor { isZed && accent == .system ? ZedPalette.accent : accent.color }
  var added: NSColor {
    diffColors == .greenRed ? (isZed ? ZedPalette.versionAdded : .systemGreen) : .systemBlue
  }
  var removed: NSColor {
    diffColors == .greenRed ? (isZed ? ZedPalette.versionDeleted : .systemRed) : .systemOrange
  }

  // MARK: Surfaces (Zed's colours in Style Zed, the system's otherwise)

  var editorBackground: NSColor { isZed ? ZedPalette.editor : .textBackgroundColor }
  /// Nil keeps the system's sidebar material.
  var panelBackground: NSColor? { isZed ? ZedPalette.panel : nil }
  var barBackground: NSColor? { isZed ? ZedPalette.tabBar : nil }
  var statusBarBackground: NSColor? { isZed ? ZedPalette.statusBar : nil }
  var titleBarBackground: NSColor? { isZed ? ZedPalette.titleBar : nil }
  var lineNumber: NSColor { isZed ? ZedPalette.lineNumber : .secondaryLabelColor }
  var separator: NSColor {
    isZed ? ZedPalette.borderVariant : NSColor.separatorColor.withAlphaComponent(0.55)
  }
  /// Git panel label colours: Zed's softer ones in Style Zed.
  var createdLabel: NSColor { isZed && diffColors == .greenRed ? ZedPalette.created : added }
  var deletedLabel: NSColor { isZed && diffColors == .greenRed ? ZedPalette.deleted : removed }
  /// The other status colours stay clear of whichever pair diffs use, so
  /// in blue and orange a rename never reads as an addition.
  var modified: NSColor {
    diffColors == .greenRed ? (isZed ? ZedPalette.modified : .systemOrange) : .systemPurple
  }
  var renamed: NSColor {
    diffColors == .greenRed ? (isZed ? ZedPalette.renamed : .systemBlue) : .systemTeal
  }
  var conflicted: NSColor { diffColors == .greenRed ? .systemRed : .systemPink }
  /// The incoming side of a merge conflict; the current side uses `added`.
  /// Blue beside green, as in Zed; purple beside blue, so the two sides
  /// never look alike.
  var incoming: NSColor { diffColors == .greenRed ? .systemBlue : .systemPurple }

  // MARK: Changing

  func set(_ appearance: Appearance) {
    self.appearance = appearance
    defaults.set(appearance.rawValue, forKey: "appearance")
    apply()
  }

  func set(_ accent: Accent) {
    self.accent = accent
    defaults.set(accent.rawValue, forKey: "accent")
    changed()
  }

  func set(_ diffColors: DiffColors) {
    self.diffColors = diffColors
    defaults.set(diffColors.rawValue, forKey: "diffColors")
    changed()
  }

  func set(_ interface: Interface) {
    self.interface = interface
    defaults.set(interface.rawValue, forKey: "interface")
    changed()
  }

  func set(_ contrast: Contrast) {
    self.contrast = contrast
    defaults.set(contrast.rawValue, forKey: "contrast")
    changed()
  }

  func setUsesLiquidGlass(_ on: Bool) {
    usesLiquidGlass = on
    defaults.set(!on, forKey: "flatToolbar")
    changed()
  }

  /// Light or dark for every window. Runs at launch and on each change.
  func apply() {
    NSApplication.shared.appearance =
      switch appearance {
      case .system: nil
      case .light: NSAppearance(named: .aqua)
      case .dark: NSAppearance(named: .darkAqua)
      }
    changed()
  }

  private func changed() {
    version += 1
    NotificationCenter.default.post(name: Self.didChange, object: nil)
  }
}

/// The app's only motion. Speed is the product, so almost nothing moves:
/// repeated paths are instant, and Reduce Motion turns this off too.
@MainActor
enum Motion {
  /// A panel growing to make room, like Minimal's commit box.
  static var reveal: Animation? {
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.15)
  }
}

extension Color {
  /// The accent you picked in Settings, in place of `Color.accentColor`.
  @MainActor static var themeAccent: Color { Color(nsColor: Theme.shared.accentColor) }
  @MainActor static var added: Color { Color(nsColor: Theme.shared.added) }
  @MainActor static var removed: Color { Color(nsColor: Theme.shared.removed) }
  /// "Has changes": the modified colour, so it never means removed.
  @MainActor static var modified: Color { Color(nsColor: Theme.shared.modified) }
}

extension View {
  /// The text levels for your contrast setting: `.secondary` and
  /// `.tertiary` below this resolve to these.
  @MainActor func themedTextLevels() -> some View {
    let theme = Theme.shared
    // Style Zed: its text, muted and placeholder colours, as in Zed.
    if theme.isZed {
      return foregroundStyle(
        Color(nsColor: ZedPalette.text), Color(nsColor: ZedPalette.textMuted),
        Color(nsColor: ZedPalette.textPlaceholder))
    }
    let contrast = theme.contrast
    return foregroundStyle(
      Color.primary, Color.primary.opacity(contrast.secondary), Color.primary.opacity(contrast.tertiary))
  }
}

/// The app's separator: one device pixel, fainter than `Divider`, so panels
/// read as areas rather than boxes. Vertical inside an `HStack`.
struct Hairline: View {
  var axis: Axis = .horizontal
  @Environment(\.displayScale) private var scale

  @MainActor static var color: Color { Color(nsColor: Theme.shared.separator) }
  @MainActor static var nsColor: NSColor { Theme.shared.separator }

  var body: some View {
    Rectangle()
      .fill(Self.color)
      .frame(
        width: axis == .vertical ? 1 / scale : nil,
        height: axis == .horizontal ? 1 / scale : nil)
  }
}
