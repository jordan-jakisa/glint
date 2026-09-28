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
      }
      Section {
        Picker("External terminal", selection: $terminal) {
          ForEach(TerminalApp.allCases) { app in
            Text(app.isInstalled ? app.name : "\(app.name) (not installed)")
              .tag(app)
              .disabled(!app.isInstalled)
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 520)
    .onChange(of: terminal) { TerminalApp.preferred = terminal }
    .onChange(of: fileOrder) { FileOrder.set(fileOrder) }
  }
}
