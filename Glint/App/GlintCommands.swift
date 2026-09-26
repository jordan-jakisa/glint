import SwiftUI

extension FocusedValues {
  /// The session of the frontmost window, for menu commands.
  @Entry var session: RepositorySession?
}

/// Menu commands, with the keys set in Settings > Shortcuts. Single keys (j,
/// k, n, p, o, Space, s, c by default) are handled by `KeyMonitor` instead,
/// so they never fire while you type a commit message.
struct GlintCommands: Commands {
  @FocusedValue(\.session) private var session

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About Glint") { AboutPanel.show() }
    }

    CommandGroup(replacing: .help) {
      Button("Acknowledgements") { AboutPanel.showAcknowledgements() }
    }

    CommandGroup(replacing: .newItem) {
      Button(AppCommand.openRepository.title) { session?.chooseRepository() }
        .shortcut(.openRepository)
        .disabled(session == nil)
      Button(AppCommand.switchProject.title) { session?.isProjectSwitcherShown = true }
        .shortcut(.switchProject)
        .disabled(!isReady)
    }

    CommandGroup(before: .toolbar) {
      Button(session?.layout == .split ? "Show Unified Diff" : "Show Split Diff") {
        session?.toggleLayout()
      }
      .shortcut(.toggleLayout)
      .disabled(!isReady)

      Button(AppCommand.reload.title) { session?.refresh() }
        .shortcut(.reload)
        .disabled(!isReady)

      Button(AppCommand.fetch.title) { session?.fetch() }
        .shortcut(.fetch)
        .disabled(!isReady)
      Button(AppCommand.pull.title) { session?.pull() }
        .shortcut(.pull)
        .disabled(!isReady)
      Button(AppCommand.push.title) { session?.push() }
        .shortcut(.push)
        .disabled(!isReady)

      Button(AppCommand.writeMessage.title) {
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
      Button(AppCommand.newTerminalTab.title) { session?.newTerminalTab() }
        .shortcut(.newTerminalTab)
        .disabled(!isReady)
      Button(AppCommand.closeTerminalTab.title) { session?.closeTerminalTab() }
        .shortcut(.closeTerminalTab)
        .disabled(!isReady || session?.isTerminalShown != true)

      Button("Open in \(TerminalApp.preferred.name)") { session?.openInTerminal() }
        .shortcut(.openExternalTerminal)
        .disabled(!isReady)

      Button(AppCommand.switchRepository.title) {
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

      Button(AppCommand.switchBranch.title) {
        session?.tab = .changes
        session?.isBranchPickerShown = true
      }
      .shortcut(.switchBranch)
      .disabled(!isReady)

      Divider()
    }

    CommandMenu("Go") {
      Group {
        Button(AppCommand.nextItem.title) { session?.selectNextItem() }
        Button(AppCommand.previousItem.title) { session?.selectPreviousItem() }

        Divider()

        Button(AppCommand.nextFile.title) { session?.nextFile() }
          .shortcut(.nextFile)
        Button(AppCommand.previousFile.title) { session?.previousFile() }
          .shortcut(.previousFile)

        Divider()

        Button(AppCommand.nextHunk.title) { session?.nextHunk() }
        Button(AppCommand.previousHunk.title) { session?.previousHunk() }

        Divider()

        Button(AppCommand.toggleCollapsed.title) { session?.toggleCurrentFileCollapsed() }

        Divider()

        Button(AppCommand.toggleStaged.title) { session?.toggleSelectedStaged() }
        Button(AppCommand.stagePartial.title) { session?.stageAtCursor() }
        Button(AppCommand.stageAll.title) { session?.stageAll() }
          .shortcut(.stageAll)
        Button(AppCommand.unstageAll.title) { session?.unstageAll() }
          .shortcut(.unstageAll)
        Button("Discard All Changes…") { session?.requestDiscardAll() }
      }
      .disabled(!isReady)
    }
  }

  private var isReady: Bool { session?.phase == .ready }
}
