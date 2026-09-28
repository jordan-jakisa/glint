import SwiftUI

/// Bottom of the Changes tab: where you are, the message, and the last commit.
struct CommitPanel: View {
  @Bindable var session: RepositorySession
  @FocusState private var messageFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      Hairline()
      // Minimal puts the branch in the status line instead.
      if !Theme.shared.isMinimal {
        BranchBar(session: session)
        Hairline()
      }
      messageEditor
      if isExpanded {
        footer
      }
      if let last = session.lastCommit {
        Hairline()
        LastCommitRow(commit: last, justCommitted: session.justCommitted, undo: session.undoLastCommit)
      }
    }
    // Grows in one step as you start a message; collapses instantly, since
    // that happens after every commit.
    .animation(isExpanded ? Motion.reveal : nil, value: isExpanded)
    .onChange(of: session.messageFocusRequest, initial: true) { _, request in
      guard let request else { return }
      messageFocused = request
      session.messageFocusRequest = nil
    }
  }

  /// Minimal keeps the box to one line until you click in or press C.
  private var isExpanded: Bool {
    !Theme.shared.isMinimal || messageFocused || !session.commitMessage.isEmpty || session.isAmending
  }

  @ViewBuilder private var footer: some View {
    if Theme.shared.isZed {
      zedFooter
    } else {
      standardFooter
    }
  }

  /// Zed's commit row: the AI button on the left, a Commit split button on
  /// the right whose menu holds Amend and Sign Off.
  private var zedFooter: some View {
    HStack(spacing: 8) {
      GenerateButton(session: session)
      Spacer()
      summaryCount
      DelayedSpinner(isActive: session.isCommitting)
      Menu {
        Toggle("Amend", isOn: $session.isAmending)
          .disabled(session.lastCommit == nil)
        Toggle("Sign Off", isOn: $session.signsOff)
      } label: {
        Text(session.commitButtonTitle)
      } primaryAction: {
        session.commit()
      }
      .menuStyle(.borderedButton)
      .fixedSize()
      .disabled(!session.canCommit && !session.isAmending)
      .help(commitHelp)
      // ⌘↩ still commits; a menu can't carry the key itself.
      Button("", action: session.commit)
        .shortcut(.commit)
        .disabled(!session.canCommit)
        .hidden()
        .frame(width: 0)
    }
    .controlSize(.small)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }

  @ViewBuilder private var summaryCount: some View {
    // Zed's 72-character guide for the summary line, as a count.
    if let summary = session.commitMessage.split(separator: "\n", omittingEmptySubsequences: false).first,
      !summary.isEmpty
    {
      Text("\(summary.count)")
        .font(.code(.caption))
        .foregroundStyle(summary.count > 72 ? Color(nsColor: Theme.shared.modified) : .secondary)
        .help(summary.count > 72 ? "The first line is over 72 characters, where git tools wrap it" : "Characters in the first line (72 fits everywhere)")
    }
  }

  @ViewBuilder private var standardFooter: some View {
    HStack(spacing: 8) {
      GenerateButton(session: session)
      Toggle("Amend", isOn: $session.isAmending)
        .toggleStyle(.checkbox)
        .fixedSize()
        .disabled(session.lastCommit == nil)
        .help("Replace the last commit instead of adding a new one")
      Toggle("Sign Off", isOn: $session.signsOff)
        .toggleStyle(.checkbox)
        .fixedSize()
        .help("Add a Signed-off-by line with your name and email")
      Spacer()
      summaryCount
      DelayedSpinner(isActive: session.isCommitting)
      Button(session.commitButtonTitle, action: session.commit)
        .shortcut(.commit)
        .disabled(!session.canCommit)
        .help(commitHelp)
    }
    .controlSize(.small)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    // Kept while AI is on, so a note arriving doesn't push the list up.
    if AISettings.shared.isEnabled || session.aiNote != nil {
      Text(session.aiNote ?? " ")
        .font(.app(.caption))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }
  }

  private var messageEditor: some View {
    TextEditor(text: $session.commitMessage)
      .font(.code(.body))
      .scrollContentBackground(.hidden)
      .focused($messageFocused)
      .frame(height: isExpanded ? 84 : 24)
      .padding(.horizontal, 6)
      .padding(.top, 6)
      .overlay(alignment: .topLeading) {
        if session.commitMessage.isEmpty {
          Text(placeholder)
            .font(.code(.body))
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.top, 6)
            .allowsHitTesting(false)
        }
      }
      .onKeyPress(.escape) {
        messageFocused = false
        return .handled
      }
  }

  /// In a workspace, says which repository the commit goes to.
  private var placeholder: String {
    guard session.workspace != nil, let name = session.info?.name else { return "Enter commit message" }
    return "Commit message for \(name)"
  }

  private var commitHelp: String {
    if session.commitsTrackedChanges {
      return AppCommand.commit.hint("Nothing is staged, so this commits every change to tracked files")
    }
    return AppCommand.commit.hint("Commit")
  }
}

private struct LastCommitRow: View {
  let commit: Commit
  let justCommitted: Bool
  let undo: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      if justCommitted {
        Label("Committed \(commit.shortID)", systemImage: "checkmark")
          .foregroundStyle(.secondary)
          .fixedSize()
      }
      Text(commit.summary)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 4)
      Button(action: undo) {
        Image(systemName: "arrow.uturn.backward")
          .hitTarget()
      }
      .buttonStyle(.borderless)
      .help("Undo this commit and keep its changes staged")
    }
    .font(.app(.callout))
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }
}

/// `repo / branch`. The branch opens the branch picker.
struct BranchBar: View {
  @Bindable var session: RepositorySession
  /// In Minimal's status line, which sets its own height and padding.
  var isInStatusLine = false

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "arrow.triangle.branch")
        .foregroundStyle(.secondary)
      if session.workspace != nil {
        Button {
          session.isRepositoryPickerShown.toggle()
        } label: {
          HStack(spacing: 2) {
            Text(session.info?.name ?? "")
              .lineLimit(1)
            if session.otherRepositoriesHaveChanges {
              Circle().fill(Color.modified).frame(width: 5, height: 5)
            }
            Image(systemName: "chevron.down")
              .font(.app(.caption2))
              .foregroundStyle(.secondary)
          }
          .frame(minHeight: 22)
          .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(AppCommand.switchRepository.hint("Switch repository"))
        .popover(isPresented: $session.isRepositoryPickerShown, arrowEdge: .top) {
          RepositoryPicker(session: session)
        }
      } else if !Theme.shared.isZed {
        // Zed shows only the branch; the project is in the title.
        Text(session.info?.name ?? "")
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      if session.workspace != nil || !Theme.shared.isZed {
        Text("/").foregroundStyle(.tertiary)
      }
      Button {
        session.isBranchPickerShown.toggle()
      } label: {
        HStack(spacing: 2) {
          Text(session.info?.branch ?? "detached HEAD")
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.app(.caption2))
            .foregroundStyle(.secondary)
        }
        .frame(minHeight: 22)
        .contentShape(Rectangle())
      }
      .buttonStyle(.borderless)
      .help(AppCommand.switchBranch.hint("Switch branch"))
      .popover(isPresented: $session.isBranchPickerShown, arrowEdge: .top) {
        BranchPicker(session: session)
      }
      Spacer()
      SyncButton(session: session)
    }
    .font(.app(.callout))
    .padding(.horizontal, isInStatusLine ? 0 : 10)
    // Matches the terminal's tab strip beside it, so the dividers line up.
    .frame(height: isInStatusLine ? nil : 30)
  }
}

/// Fetch, Pull, or Push, whichever fits, with the others in its menu.
private struct SyncButton: View {
  @Bindable var session: RepositorySession

  var body: some View {
    // One control throughout: while git works it's disabled and says what's
    // happening, then says how it went for a moment.
    Group {
      if Theme.shared.isFlat {
        menu.menuStyle(.borderlessButton)
      } else {
        menu.menuStyle(.borderedButton)
      }
    }
    .controlSize(.small)
    .fixedSize()
    .disabled(session.networkOperation != nil)
    .help(help)
  }

  private var menu: some View {
    Menu {
      Button("Fetch", action: session.fetch)
      Button("Pull", action: session.pull)
      Button("Pull with Rebase", action: session.pullRebase)
      Button(session.sync.upstream == nil ? "Publish Branch" : "Push", action: session.push)
      Button("Force Push", action: session.forcePush)
        .disabled(session.sync.upstream == nil && session.chosenRemote == nil)
      // Zed's remote picker, when there's more than one remote.
      if session.remotes.count > 1 {
        Divider()
        Picker("Remote", selection: $session.selectedRemote) {
          Text("Upstream").tag(String?.none)
          ForEach(session.remotes, id: \.self) { Text($0).tag(Optional($0)) }
        }
        .pickerStyle(.inline)
      }
    } label: {
      Label(title, systemImage: icon)
        .labelStyle(.titleAndIcon)
    } primaryAction: {
      session.runSuggestedSync()
    }
  }

  private var title: String {
    if let operation = session.networkOperation { return operation.rawValue + "…" }
    switch session.syncOutcome {
    case .pushed(let count): return count > 0 ? "Pushed \(count)" : "Pushed"
    case .pulled(let count): return count > 0 ? "Pulled \(count)" : "Pulled"
    case .fetched where session.sync.behind == 0: return "Up to date"
    default: return session.suggestedSyncTitle
    }
  }

  private var icon: String {
    if session.networkOperation == nil, let outcome = session.syncOutcome,
      outcome != .fetched || session.sync.behind == 0
    {
      return "checkmark"
    }
    return switch session.suggestedSync {
    case .pull: "arrow.down"
    case .push: "arrow.up"
    case .fetch: "arrow.triangle.2.circlepath"
    }
  }

  private var help: String {
    guard let upstream = session.sync.upstream else {
      return session.sync.hasRemotes ? "This branch isn't on a remote yet" : "No remote configured"
    }
    return "\(session.sync.ahead) ahead, \(session.sync.behind) behind \(upstream)"
  }
}

/// Writes the message with the free model picked in Settings. Without setup,
/// it opens Settings instead.
private struct GenerateButton: View {
  @Bindable var session: RepositorySession
  @Environment(\.openSettings) private var openSettings
  private let settings = AISettings.shared

  var body: some View {
    Button {
      if settings.isReady || session.isGeneratingMessage {
        session.generateCommitMessage()
      } else {
        openSettings()
      }
    } label: {
      // Sparkles pulse while writing; the tooltip says a click stops it.
      Image(systemName: "sparkles")
        .symbolEffect(.pulse, isActive: session.isGeneratingMessage)
        .hitTarget()
    }
    .buttonStyle(.borderless)
    .help(help)
  }

  private var help: String {
    if session.isGeneratingMessage { return "Stop writing" }
    guard settings.isReady, let model = settings.modelID else { return settings.setupHint }
    return AppCommand.writeMessage.hint("Write the message with \(model) on \(settings.provider.name)")
      + ". Sends your diff there."
  }
}
