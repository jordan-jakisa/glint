import SwiftUI

extension FocusedValues {
  /// The session of the frontmost window, for menu commands.
  @Entry var session: RepositorySession?
}

/// Menu commands. Single-letter keys (j, k, n, p, o, Space) are handled by
/// `KeyMonitor` instead, so they never fire while you type a commit message.
struct AditCommands: Commands {
  @FocusedValue(\.session) private var session

  var body: some Commands {
    CommandGroup(replacing: .newItem) {
      Button("Open Repository…") { session?.chooseRepository() }
        .keyboardShortcut("o")
        .disabled(session == nil)
    }

    CommandGroup(before: .toolbar) {
      Button(session?.layout == .split ? "Show Unified Diff" : "Show Split Diff") {
        session?.toggleLayout()
      }
      .keyboardShortcut("\\")
      .disabled(!isReady)

      Button("Reload") { session?.refresh() }
        .keyboardShortcut("r")
        .disabled(!isReady)

      Button("Fetch") { session?.fetch() }
        .keyboardShortcut("f", modifiers: [.command, .option])
        .disabled(!isReady)
      Button("Pull") { session?.pull() }
        .keyboardShortcut("p", modifiers: [.command, .option])
        .disabled(!isReady)
      Button("Push") { session?.push() }
        .keyboardShortcut("p", modifiers: [.command, .option, .shift])
        .disabled(!isReady)

      Button("Write Commit Message with AI") {
        session?.tab = .changes
        session?.generateCommitMessage()
      }
      .keyboardShortcut("g", modifiers: [.command, .option])
      .disabled(!isReady)

      Button(session?.isTerminalShown == true ? "Hide Terminal" : "Show Terminal") {
        session?.isTerminalShown.toggle()
      }
      .keyboardShortcut("t")
      .disabled(!isReady)

      Button("Open in \(TerminalApp.preferred.name)") { session?.openInTerminal() }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .disabled(!isReady)

      Button("Switch Repository…") {
        session?.tab = .changes
        session?.isRepositoryPickerShown = true
      }
      .keyboardShortcut("r", modifiers: [.command, .shift])
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
      .keyboardShortcut("b")
      .disabled(!isReady)

      Divider()
    }

    CommandMenu("Go") {
      Group {
        Button("Next Item") { session?.selectNextItem() }
        Button("Previous Item") { session?.selectPreviousItem() }

        Divider()

        Button("Next File") { session?.nextFile() }
          .keyboardShortcut(.downArrow)
        Button("Previous File") { session?.previousFile() }
          .keyboardShortcut(.upArrow)

        Divider()

        Button("Next Hunk") { session?.nextHunk() }
        Button("Previous Hunk") { session?.previousHunk() }

        Divider()

        Button("Collapse or Expand File") { session?.toggleCurrentFileCollapsed() }

        Divider()

        Button("Stage or Unstage File") { session?.toggleSelectedStaged() }
        Button("Stage or Unstage Hunk or Lines") { session?.stageAtCursor() }
        Button("Stage All") { session?.stageAll() }
          .keyboardShortcut("s", modifiers: [.command, .option])
        Button("Unstage All") { session?.unstageAll() }
          .keyboardShortcut("u", modifiers: [.command, .option])
        Button("Discard All Changes…") { session?.requestDiscardAll() }
      }
      .disabled(!isReady)
    }
  }

  private var isReady: Bool { session?.phase == .ready }
}
