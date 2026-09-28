import SwiftUI

/// Settings, Appearance tab.
struct AppearanceSettingsView: View {
  private let theme = Theme.shared
  private let textSize = TextSize.shared

  var body: some View {
    Form {
      Section {
        Picker(
          "Interface", selection: Binding(get: { theme.interface }, set: { theme.set($0) })
        ) {
          ForEach(Theme.Interface.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .help(AppCommand.toggleMinimal.hint("Minimal: no toolbar, one status line along the bottom"))
        Picker(
          "Theme", selection: Binding(get: { theme.appearance }, set: { theme.set($0) })
        ) {
          ForEach(Theme.Appearance.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        LabeledContent("Accent") {
          HStack(spacing: 4) {
            ForEach(Theme.Accent.allCases) { accent in
              Swatch(color: accent.color, isSelected: theme.accent == accent) { theme.set(accent) }
                .help(accent.title)
                .accessibilityLabel("\(accent.title) accent")
            }
          }
        }
        Picker(
          "Text contrast", selection: Binding(get: { theme.contrast }, set: { theme.set($0) })
        ) {
          ForEach(Theme.Contrast.allCases) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        Picker(
          "Diff colors", selection: Binding(get: { theme.diffColors }, set: { theme.set($0) })
        ) {
          ForEach(Theme.DiffColors.allCases) { Text($0.title).tag($0) }
        }
      }
      Section {
        LabeledContent("Text size") {
          HStack(spacing: 6) {
            if textSize.body != TextSize.standard {
              Button(action: textSize.reset) {
                Image(systemName: "arrow.uturn.backward").hitTarget()
              }
              .accessibilityLabel("Default text size")
              .buttonStyle(.borderless)
              .help("Back to \(Int(TextSize.standard)) pt")
            }
            Text("\(Int(textSize.body)) pt").foregroundStyle(.secondary).monospacedDigit()
            Stepper(
              "Text size", value: Binding(get: { textSize.body }, set: textSize.set), in: TextSize.range,
              step: 1
            )
            .labelsHidden()
          }
        }
        .help("\(AppCommand.biggerText.keys) and \(AppCommand.smallerText.keys) change it from anywhere")
      }
      Section {
        Toggle(
          "Liquid Glass toolbar",
          isOn: Binding(get: { theme.usesLiquidGlass }, set: { theme.setUsesLiquidGlass($0) }))
      }
    }
    .formStyle(.grouped)
    .frame(width: 520)
  }
}

private struct Swatch: View {
  let color: NSColor
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      Circle()
        .fill(Color(nsColor: color))
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
