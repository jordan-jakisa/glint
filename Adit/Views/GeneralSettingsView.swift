import SwiftUI

/// Settings, General tab.
struct GeneralSettingsView: View {
  @State private var terminal = TerminalApp.preferred
  @State private var fileOrder = FileOrder.current

  var body: some View {
    Form {
      Section {
        Picker("File order", selection: $fileOrder) {
          Text("Most useful first").tag(FileOrder.smart)
          Text("By path").tag(FileOrder.path)
        }
        Text("Most useful first puts source files first, each followed by its tests, then config and docs, with lockfiles and vendored code last. Files further down a review get less attention.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      Section {
        Picker("External terminal", selection: $terminal) {
          ForEach(TerminalApp.allCases) { app in
            Text(app.isInstalled ? app.name : "\(app.name) (not installed)")
              .tag(app)
              .disabled(!app.isInstalled)
          }
        }
        Text(terminalNote)
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(width: 520)
    .onChange(of: terminal) { TerminalApp.preferred = terminal }
    .onChange(of: fileOrder) { FileOrder.set(fileOrder) }
  }

  private var terminalNote: String {
    let builtIn = AppCommand.showTerminal.keys
    let external = AppCommand.openExternalTerminal.keys
    return [
      builtIn.isEmpty ? nil : "\(builtIn) shows Adit's own terminal.",
      external.isEmpty ? nil : "\(external) opens the active repository in this app instead.",
    ].compactMap { $0 }.joined(separator: " ")
  }
}
