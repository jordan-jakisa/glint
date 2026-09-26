import SwiftUI

extension FocusedValues {
  /// The session of the frontmost window, for menu commands.
  @Entry var session: RepositorySession?
}

/// Menu commands, with the keys set in Settings > Shortcuts. Single keys (j,
/// k, n, p, o, Space, s, c by default) are handled by `KeyMonitor` instead,
/// so they never fire while you type a commit message.
struct AditCommands: Commands {
  @FocusedValue(\.session) private var session

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Adit") { AboutPanel.show() }
    }

    CommandGroup(replacing: .newItem) {
      Button("Open Repository…") { session?.chooseRepository() }
        .shortcut(.openRepository)
        .disabled(session == nil)
    }

    CommandGroup(before: .toolbar) {
      Button(session?.layout == .split ? "Show Unified Diff" : "Show Split Diff") {
        session?.toggleLayout()
      }
      .shortcut(.toggleLayout)
      .disabled(!isReady)

      Button("Reload") { session?.refresh() }
        .shortcut(.reload)
        .disabled(!isReady)

      Button("Fetch") { session?.fetch() }
        .shortcut(.fetch)
        .disabled(!isReady)
      Button("Pull") { session?.pull() }
        .shortcut(.pull)
        .disabled(!isReady)
      Button("Push") { session?.push() }
        .shortcut(.push)
        .disabled(!isReady)

      Button("Write Commit Message with AI") {
        session?.tab = .changes
        session?.generateCommitMessage()
      }
      .shortcut(.writeMessage)
      .disabled(!isReady)

      Button(session?.isTerminalShown == true ? "Hide Terminal" : "Show Terminal") {
        session?.isTerminalShown.toggle()
      }
      .shortcut(.showTerminal)
      .disabled(!isReady)

      Button("Open in \(TerminalApp.preferred.name)") { session?.openInTerminal() }
        .shortcut(.openExternalTerminal)
        .disabled(!isReady)

      Button("Switch Repository…") {
        session?.tab = .changes
        session?.isRepositoryPickerShown = true
      }
      .shortcut(.switchRepository)
      .disabled(!isReady || session?.workspace == nil)

      ForEach(0..<9, id: \.self) { index in
        if let repositories = session?.workspace?.repositories, index < repositories.count {
          Button(repositories[index].relativePath) { session?.switchRepository(at: index) }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
      }

      Button("Switch Branch…") {
        session?.tab = .changes
        session?.isBranchPickerShown = true
      }
      .shortcut(.switchBranch)
      .disabled(!isReady)

      Divider()
    }

    CommandMenu("Go") {
      Group {
        Button("Next Item") { session?.selectNextItem() }
        Button("Previous Item") { session?.selectPreviousItem() }

        Divider()

        Button("Next File") { session?.nextFile() }
          .shortcut(.nextFile)
        Button("Previous File") { session?.previousFile() }
          .shortcut(.previousFile)

        Divider()

        Button("Next Hunk") { session?.nextHunk() }
        Button("Previous Hunk") { session?.previousHunk() }

        Divider()

        Button("Collapse or Expand File") { session?.toggleCurrentFileCollapsed() }

        Divider()

        Button("Stage or Unstage File") { session?.toggleSelectedStaged() }
        Button("Stage or Unstage Hunk or Lines") { session?.stageAtCursor() }
        Button("Stage All") { session?.stageAll() }
          .shortcut(.stageAll)
        Button("Unstage All") { session?.unstageAll() }
          .shortcut(.unstageAll)
        Button("Discard All Changes…") { session?.requestDiscardAll() }
      }
      .disabled(!isReady)
    }
  }

  private var isReady: Bool { session?.phase == .ready }
}
