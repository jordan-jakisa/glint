import SwiftUI

extension FocusedValues {
  /// The session of the frontmost window, for menu commands.
  @Entry var session: RepositorySession?
}

/// Every action has a key. Plain letters work because Adit has no text fields
/// to type into.
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

      Divider()
    }

    CommandMenu("Go") {
      Group {
        Button("Next Item") { session?.selectNextItem() }
          .keyboardShortcut("j", modifiers: [])
        Button("Previous Item") { session?.selectPreviousItem() }
          .keyboardShortcut("k", modifiers: [])

        Divider()

        Button("Next File") { session?.nextFile() }
          .keyboardShortcut(.downArrow)
        Button("Previous File") { session?.previousFile() }
          .keyboardShortcut(.upArrow)

        Divider()

        Button("Next Hunk") { session?.nextHunk() }
          .keyboardShortcut("n", modifiers: [])
        Button("Previous Hunk") { session?.previousHunk() }
          .keyboardShortcut("p", modifiers: [])

        Divider()

        Button("Collapse or Expand File") { session?.toggleCurrentFileCollapsed() }
          .keyboardShortcut("o", modifiers: [])
      }
      .disabled(!isReady)
    }
  }

  private var isReady: Bool { session?.phase == .ready }
}
