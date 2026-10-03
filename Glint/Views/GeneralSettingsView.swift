import SwiftUI

/// Settings, General: every preference a window keeps, in one place.
/// Changes reach open windows straight away.
struct GeneralSettingsView: View {
  @State private var terminal = TerminalApp.preferred
  @State private var fileOrder = FileOrder.current
  @AppStorage("diffLayout") private var layout = DiffLayout.split
  @AppStorage("gitPanelTree") private var isTree = false
  @AppStorage("wordDiff") private var wordDiff = true
  @AppStorage("syntaxHighlighting") private var syntaxHighlighting = true
  @AppStorage("autosave") private var autosave = true
  @AppStorage("notebookPython") private var notebookPython = ""
  @AppStorage("showsAllRepositories") private var showsAllRepositories = false
  @AppStorage("terminalShown") private var terminalShown = false
  @State private var recentsCleared = false

  var body: some View {
    SettingsPage(title: "General") {
      SettingsSection(title: "Changes")
      SettingsRow(
        title: "File order", description: "Source first puts code before its tests, config and lockfiles.",
        isModified: fileOrder != .smart, reset: { fileOrder = .smart }
      ) {
        Picker("File order", selection: $fileOrder) {
          Text("Source first").tag(FileOrder.smart)
          Text("By path").tag(FileOrder.path)
          Text("By name").tag(FileOrder.name)
        }
        .labelsHidden()
        .fixedSize()
      }
      SettingsRow(
        title: "Diff layout", description: AppCommand.toggleLayout.hint("Side by side or in one column"),
        isModified: layout != .split, reset: { layout = .split }
      ) {
        Picker("Diff layout", selection: $layout) {
          Text("Unified").tag(DiffLayout.unified)
          Text("Split").tag(DiffLayout.split)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      SettingsRow(
        title: "Changes list", description: "In Style Zed, list files flat or by folder.",
        isModified: isTree, reset: { isTree = false }
      ) {
        Picker("Changes list", selection: $isTree) {
          Text("Flat").tag(false)
          Text("Tree").tag(true)
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .fixedSize()
      }
      SettingsRow(
        title: "Highlight changed words", description: "Marks the words that changed inside a line.",
        isModified: !wordDiff, reset: { wordDiff = true }
      ) {
        Toggle("Highlight changed words", isOn: $wordDiff).labelsHidden().toggleStyle(.switch)
      }
      SettingsRow(
        title: "Syntax colours", description: "Colours code in diffs and the editor, like Zed's One theme.",
        isModified: !syntaxHighlighting, reset: { syntaxHighlighting = true }
      ) {
        Toggle("Syntax colours", isOn: $syntaxHighlighting).labelsHidden().toggleStyle(.switch)
      }
      SettingsRow(
        title: "Show every repository's changes",
        description: "In a folder of repositories, lists the others' changes too.",
        isModified: showsAllRepositories, reset: { showsAllRepositories = false }
      ) {
        Toggle("Show every repository's changes", isOn: $showsAllRepositories).labelsHidden().toggleStyle(.switch)
      }

      SettingsSection(title: "Editor")
      SettingsRow(
        title: "Autosave", description: "Saves a file a second after you stop typing. Otherwise \u{2318}S.",
        isModified: !autosave, reset: { autosave = true }
      ) {
        Toggle("Autosave", isOn: $autosave).labelsHidden().toggleStyle(.switch)
      }
      SettingsRow(
        title: "Python for notebooks",
        description: "Runs notebook cells. Empty: the project's .venv, then Glint's own, then python3.",
        isModified: !notebookPython.isEmpty, reset: { notebookPython = "" }
      ) {
        TextField("Automatic", text: $notebookPython)
          .labelsHidden()
          .frame(width: 220)
      }

      SettingsSection(title: "Terminal")
      SettingsRow(
        title: "Show the terminal", description: AppCommand.showTerminal.hint("Under the diff"),
        isModified: terminalShown, reset: { terminalShown = false }
      ) {
        Toggle("Show the terminal", isOn: $terminalShown).labelsHidden().toggleStyle(.switch)
      }
      SettingsRow(
        title: "External terminal", description: AppCommand.openExternalTerminal.hint("Opens the repository in this app")
      ) {
        Picker("External terminal", selection: $terminal) {
          ForEach(TerminalApp.allCases) { app in
            Text(app.isInstalled ? app.name : "\(app.name) (not installed)")
              .tag(app)
              .disabled(!app.isInstalled)
          }
        }
        .labelsHidden()
        .fixedSize()
      }

      SettingsSection(title: "Projects")
      SettingsRow(title: "Recent projects", description: "Forgets every project but the one open now.") {
        Button(recentsCleared ? "Cleared" : "Clear") {
          RepositoryAccess().clearOlderRecents()
          recentsCleared = true
        }
        .disabled(recentsCleared)
      }
    }
    .onChange(of: terminal) { TerminalApp.preferred = terminal }
    .onChange(of: fileOrder) {
      FileOrder.set(fileOrder)
      preferencesChanged()
    }
    .onChange(of: layout) { preferencesChanged() }
    .onChange(of: showsAllRepositories) { preferencesChanged() }
    .onChange(of: terminalShown) { preferencesChanged() }
    .onChange(of: wordDiff) { preferencesChanged() }
    .onChange(of: syntaxHighlighting) { preferencesChanged() }
  }

  private func preferencesChanged() {
    NotificationCenter.default.post(name: RepositorySession.preferencesChanged, object: nil)
  }
}
