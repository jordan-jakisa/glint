import SwiftUI

/// Settings, Appearance tab.
struct AppearanceSettingsView: View {
  private let theme = Theme.shared
  private let textSize = TextSize.shared

  var body: some View {
    SettingsPage(title: "Appearance") {
      SettingsSection(title: "Look")
      SettingsRow(
        title: "Style", description: "macOS uses Liquid Glass; Zed is flat, in One Dark and One Light.",
        isModified: !theme.usesLiquidGlass, reset: { theme.setUsesLiquidGlass(true) }
      ) {
        Picker("Style", selection: Binding(get: { theme.usesLiquidGlass }, set: { theme.setUsesLiquidGlass($0) })) {
          Text("macOS").tag(true)
          Text("Zed").tag(false)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      SettingsRow(
        title: "Interface", description: AppCommand.toggleMinimal.hint("Minimal drops the toolbar for a status line"),
        isModified: theme.interface != .standard, reset: { theme.set(Theme.Interface.standard) }
      ) {
        Picker("Interface", selection: Binding(get: { theme.interface }, set: { theme.set($0) })) {
          ForEach(Theme.Interface.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      SettingsRow(
        title: "Theme", description: "Light, dark, or whatever your Mac uses.",
        isModified: theme.appearance != .system, reset: { theme.set(Theme.Appearance.system) }
      ) {
        Picker("Theme", selection: Binding(get: { theme.appearance }, set: { theme.set($0) })) {
          ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      SettingsRow(
        title: "Accent", description: "Selection, highlights and the terminal cursor.",
        isModified: theme.accent != .system, reset: { theme.set(Theme.Accent.system) }
      ) {
        HStack(spacing: 4) {
          ForEach(Theme.Accent.allCases) { accent in
            Swatch(accent: accent, isSelected: theme.accent == accent) { theme.set(accent) }
              .help(accent.title)
              .accessibilityLabel("\(accent.title) accent")
          }
        }
      }
      SettingsRow(
        title: "Diff colors", description: "Blue and orange stay apart for red-green colour blindness.",
        isModified: theme.diffColors != .greenRed, reset: { theme.set(Theme.DiffColors.greenRed) }
      ) {
        Picker("Diff colors", selection: Binding(get: { theme.diffColors }, set: { theme.set($0) })) {
          ForEach(Theme.DiffColors.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
      }

      SettingsSection(title: "Text")
      SettingsRow(
        title: "Text size",
        description: "\(AppCommand.biggerText.keys) and \(AppCommand.smallerText.keys) change it from anywhere.",
        isModified: textSize.body != TextSize.standard, reset: textSize.reset
      ) {
        HStack(spacing: 6) {
          Text("\(Int(textSize.body)) pt").foregroundStyle(.secondary).monospacedDigit()
          Stepper(
            "Text size", value: Binding(get: { textSize.body }, set: textSize.set), in: TextSize.range, step: 1
          )
          .labelsHidden()
        }
      }
      SettingsRow(
        title: "Text contrast", description: "How strong secondary text is, outside Style Zed.",
        isModified: theme.contrast != .standard, reset: { theme.set(Theme.Contrast.standard) }
      ) {
        Picker("Text contrast", selection: Binding(get: { theme.contrast }, set: { theme.set($0) })) {
          ForEach(Theme.Contrast.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
    }
  }
}

private struct Swatch: View {
  let accent: Theme.Accent
  let isSelected: Bool
  let select: () -> Void

  /// System looks like macOS's own multicolor swatch, so it doesn't read as a
  /// copy of whichever colour your Mac happens to use.
  @ViewBuilder private var dot: some View {
    if accent == .system {
      Circle().fill(
        AngularGradient(
          colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red], center: .center))
    } else {
      Circle().fill(Color(nsColor: accent.color))
    }
  }

  var body: some View {
    Button(action: select) {
      dot
        .frame(width: 16, height: 16)
        .overlay {
          Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.8 : 0), lineWidth: 2).padding(-3)
        }
        // A 22 pt target around the 16 pt dot, with room for the ring.
        .frame(width: 26, height: 26)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
