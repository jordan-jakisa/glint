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

  var accentColor: NSColor { accent.color }
  var added: NSColor { diffColors == .greenRed ? .systemGreen : .systemBlue }
  var removed: NSColor { diffColors == .greenRed ? .systemRed : .systemOrange }

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

extension Color {
  /// The accent you picked in Settings, in place of `Color.accentColor`.
  @MainActor static var themeAccent: Color { Color(nsColor: Theme.shared.accentColor) }
  @MainActor static var added: Color { Color(nsColor: Theme.shared.added) }
  @MainActor static var removed: Color { Color(nsColor: Theme.shared.removed) }
}

extension View {
  /// The text levels for your contrast setting: `.secondary` and
  /// `.tertiary` below this resolve to these.
  @MainActor func themedTextLevels() -> some View {
    let contrast = Theme.shared.contrast
    return foregroundStyle(
      Color.primary, Color.primary.opacity(contrast.secondary), Color.primary.opacity(contrast.tertiary))
  }
}

/// The app's separator: one device pixel, fainter than `Divider`, so panels
/// read as areas rather than boxes. Vertical inside an `HStack`.
struct Hairline: View {
  var axis: Axis = .horizontal
  @Environment(\.displayScale) private var scale

  static let color = Color(nsColor: .separatorColor).opacity(0.55)
  static let nsColor = NSColor.separatorColor.withAlphaComponent(0.55)

  var body: some View {
    Rectangle()
      .fill(Self.color)
      .frame(
        width: axis == .vertical ? 1 / scale : nil,
        height: axis == .horizontal ? 1 / scale : nil)
  }
}
