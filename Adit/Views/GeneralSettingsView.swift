import SwiftUI

/// Settings, General tab.
struct GeneralSettingsView: View {
  @State private var terminal = TerminalApp.preferred

  var body: some View {
    Form {
      Section {
        Picker("Open in Terminal uses", selection: $terminal) {
          ForEach(TerminalApp.allCases) { app in
            Text(app.isInstalled ? app.name : "\(app.name) (not installed)")
              .tag(app)
              .disabled(!app.isInstalled)
          }
        }
        Text("\u{2318}T opens the active repository there.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 520)
    .onChange(of: terminal) { TerminalApp.preferred = terminal }
  }
}
