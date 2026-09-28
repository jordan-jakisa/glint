import SwiftUI

/// Settings, General tab: every preference a window keeps, in one place.
/// Changes reach open windows straight away.
struct GeneralSettingsView: View {
  @State private var terminal = TerminalApp.preferred
  @State private var fileOrder = FileOrder.current
  @AppStorage("diffLayout") private var layout = DiffLayout.unified
  @AppStorage("showsAllRepositories") private var showsAllRepositories = false
  @AppStorage("terminalShown") private var terminalShown = false
  @State private var recentsCleared = false

  var body: some View {
    Form {
      Section("Changes") {
        Picker("File order", selection: $fileOrder) {
          Text("Source first").tag(FileOrder.smart)
          Text("By path").tag(FileOrder.path)
        }
        .help("Source files first, each followed by its tests, then config and docs, lockfiles last")
        Picker("Diff layout", selection: $layout) {
          Text("Unified").tag(DiffLayout.unified)
          Text("Split").tag(DiffLayout.split)
        }
        .pickerStyle(.segmented)
        .help(AppCommand.toggleLayout.hint("Also in the toolbar"))
        Toggle("Show every repository's changes", isOn: $showsAllRepositories)
          .help("In a folder of repositories, list the others' changes under the active one's")
      }
      Section("Terminal") {
        Toggle("Show the terminal", isOn: $terminalShown)
          .help(AppCommand.showTerminal.hint("Under the diff"))
        Picker("External terminal", selection: $terminal) {
          ForEach(TerminalApp.allCases) { app in
            Text(app.isInstalled ? app.name : "\(app.name) (not installed)")
              .tag(app)
              .disabled(!app.isInstalled)
          }
        }
        .help(AppCommand.openExternalTerminal.hint("Opens the active repository in this app"))
      }
      Section("Projects") {
        LabeledContent("Recent projects") {
          Button(recentsCleared ? "Cleared" : "Clear") {
            RepositoryAccess().clearOlderRecents()
            recentsCleared = true
          }
          .disabled(recentsCleared)
        }
        .help("Forgets every project but the one open now")
      }
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .fixedSize(horizontal: false, vertical: true)
    .onChange(of: terminal) { TerminalApp.preferred = terminal }
    .onChange(of: fileOrder) { FileOrder.set(fileOrder) }
    .onChange(of: layout) { preferencesChanged() }
    .onChange(of: showsAllRepositories) { preferencesChanged() }
    .onChange(of: terminalShown) { preferencesChanged() }
  }

  private func preferencesChanged() {
    NotificationCenter.default.post(name: RepositorySession.preferencesChanged, object: nil)
  }
}
