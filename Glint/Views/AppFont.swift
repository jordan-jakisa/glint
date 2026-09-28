import AppKit
import CoreText
import SwiftUI

/// Your text size, from Settings or ⌘+ and ⌘-. It's the body size; the
/// rest of the scale keeps its distance from it.
@MainActor
@Observable
final class TextSize {
  static let shared = TextSize()
  static let standard: CGFloat = 14
  static let range: ClosedRange<CGFloat> = 10...20
  static let didChange = Notification.Name("GlintTextSizeDidChange")
  private static let key = "textSize"

  /// Changed through `set(_:)`, which clamps it. Clamping in `didSet`
  /// would call the observed setter again, forever.
  private(set) var body: CGFloat

  func set(_ size: CGFloat) {
    let clamped = min(max(size.rounded(), Self.range.lowerBound), Self.range.upperBound)
    guard clamped != body else { return }
    body = clamped
    UserDefaults.standard.set(Double(clamped), forKey: Self.key)
    NotificationCenter.default.post(name: Self.didChange, object: nil)
  }

  private init() {
    let saved = UserDefaults.standard.double(forKey: Self.key)
    body = Self.range.contains(saved) ? saved : Self.standard
  }

  func step(_ points: CGFloat) { set(body + points) }
  func reset() { set(Self.standard) }
}

/// JetBrains Mono, bundled, for the whole app: the interface, diffs, commit
/// messages, and the terminal. Bundled rather than looked up, so it looks the
/// same on a Mac that doesn't have it installed.
@MainActor
enum AppFont {
  static let family = "JetBrains Mono"

  /// Registers the bundled faces for this process. Runs before any view
  /// draws, so no text lays out in the fallback first.
  static func register() {
    for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }

  /// The whole type scale: four sizes, two weights, all following your
  /// text size (14 by default, giving 12, 14, 18, 28). Hierarchy past that
  /// comes from colour (primary, secondary, tertiary), not more sizes.
  static var body: CGFloat { TextSize.shared.body }
  static var small: CGFloat { body - 2 }
  static var title: CGFloat { body + 4 }
  static var display: CGFloat { body * 2 }

  /// For AppKit drawing. Semibold or heavier gets SemiBold, anything
  /// lighter Regular. Falls back to the system monospace if a face is
  /// missing, so a broken bundle still reads as code.
  nonisolated static func ns(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    let face = weight >= .semibold ? "JetBrainsMono-SemiBold" : "JetBrainsMono-Regular"
    return NSFont(name: face, size: size) ?? .monospacedSystemFont(ofSize: size, weight: weight)
  }

  /// SwiftUI's text styles folded onto the scale. 12 pt JetBrains Mono sits
  /// where 13 pt SF Pro does, since a monospace face runs wider.
  static func size(_ style: Font.TextStyle) -> CGFloat {
    switch style {
    case .largeTitle: display
    case .title, .title2, .title3: title
    case .footnote, .caption, .caption2: small
    default: body
    }
  }

  /// Headlines and titles are semibold; everything else is regular.
  static func isSemibold(_ style: Font.TextStyle) -> Bool {
    switch style {
    case .largeTitle, .title, .title2, .title3, .headline: true
    default: false
    }
  }
}

extension Font {
  /// The app's font for a text style, in place of the system one.
  @MainActor
  static func app(_ style: Font.TextStyle) -> Font {
    let font = Font.custom(AppFont.family, size: AppFont.size(style), relativeTo: style)
    return AppFont.isSemibold(style) ? font.weight(.semibold) : font
  }
}

/// `ContentUnavailableView` in the app font. The built-in one sets its own
/// fonts on the title and description, so they're set again closer in.
struct EmptyState<LabelContent: View, Description: View, Actions: View>: View {
  @ViewBuilder let label: LabelContent
  @ViewBuilder let description: Description
  @ViewBuilder let actions: Actions

  var body: some View {
    // Minimal: the line of text and its one action, no icon or title.
    if Theme.shared.isMinimal {
      VStack(spacing: 8) {
        description
          .font(.app(.body))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        actions
          .buttonStyle(.link)
      }
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      standard
    }
  }

  private var standard: some View {
    ContentUnavailableView {
      label.font(.app(.title2))
    } description: {
      description.font(.app(.body))
    } actions: {
      actions
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension EmptyState where LabelContent == Label<Text, Image>, Description == Text, Actions == EmptyView {
  init(_ title: String, systemImage: String, description: Text) {
    self.init {
      Label(title, systemImage: systemImage)
    } description: {
      description
    } actions: {
      EmptyView()
    }
  }
}
