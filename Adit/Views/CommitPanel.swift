import SwiftUI

/// Bottom of the Changes tab: where you are, the message, and the last commit.
struct CommitPanel: View {
  @Bindable var session: RepositorySession
  @FocusState private var messageFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      Divider()
      BranchBar(session: session)
      Divider()
      messageEditor
      HStack(spacing: 8) {
        GenerateButton(session: session)
        Toggle("Amend", isOn: $session.isAmending)
          .toggleStyle(.checkbox)
          .disabled(session.lastCommit == nil)
          .help("Replace the last commit instead of adding a new one")
        Spacer()
        if session.isCommitting {
          ProgressView().controlSize(.small)
        }
        Button(session.commitButtonTitle, action: session.commit)
          .keyboardShortcut(.return, modifiers: .command)
          .disabled(!session.canCommit)
          .help(commitHelp)
      }
      .controlSize(.small)
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      if let last = session.lastCommit {
        Divider()
        LastCommitRow(commit: last, undo: session.undoLastCommit)
      }
    }
    .onChange(of: session.commitFocusRequest) { messageFocused = true }
  }

  private var messageEditor: some View {
    TextEditor(text: $session.commitMessage)
      .font(.body)
      .scrollContentBackground(.hidden)
      .focused($messageFocused)
      .frame(height: 84)
      .padding(.horizontal, 6)
      .padding(.top, 6)
      .overlay(alignment: .topLeading) {
        if session.commitMessage.isEmpty {
          Text("Enter commit message")
            .foregroundStyle(.tertiary)
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

  private var commitHelp: String {
    if session.commitsTrackedChanges {
      return "Nothing is staged, so this commits every change to tracked files (⌘↩)"
    }
    return "⌘↩"
  }
}

private struct LastCommitRow: View {
  let commit: Commit
  let undo: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Text(commit.summary)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 4)
      Button(action: undo) {
        Image(systemName: "arrow.uturn.backward")
      }
      .buttonStyle(.borderless)
      .help("Undo this commit and keep its changes staged")
    }
    .font(.callout)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }
}

/// `repo / branch`. The branch opens the branch picker.
struct BranchBar: View {
  @Bindable var session: RepositorySession

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
              Circle().fill(.orange).frame(width: 5, height: 5)
            }
            Image(systemName: "chevron.down")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help("Switch repository (\u{21E7}\u{2318}R)")
        .popover(isPresented: $session.isRepositoryPickerShown, arrowEdge: .top) {
          RepositoryPicker(session: session)
        }
      } else {
        Text(session.info?.name ?? "")
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Text("/").foregroundStyle(.tertiary)
      Button {
        session.isBranchPickerShown.toggle()
      } label: {
        HStack(spacing: 2) {
          Text(session.info?.branch ?? "detached HEAD")
            .lineLimit(1)
          Image(systemName: "chevron.down")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.borderless)
      .help("Switch branch (⌘B)")
      .popover(isPresented: $session.isBranchPickerShown, arrowEdge: .top) {
        BranchPicker(session: session)
      }
      Spacer()
      SyncButton(session: session)
    }
    .font(.callout)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }
}

/// Fetch, Pull, or Push, whichever fits, with the others in its menu.
private struct SyncButton: View {
  @Bindable var session: RepositorySession

  var body: some View {
    if let operation = session.networkOperation {
      HStack(spacing: 4) {
        ProgressView().controlSize(.mini)
        Text(operation.rawValue + "…").foregroundStyle(.secondary)
      }
    } else {
      Menu {
        Button("Fetch", action: session.fetch)
        Button("Pull", action: session.pull)
        Button(session.sync.upstream == nil ? "Publish Branch" : "Push", action: session.push)
      } label: {
        Label(session.suggestedSyncTitle, systemImage: icon)
      } primaryAction: {
        session.runSuggestedSync()
      }
      .menuStyle(.borderedButton)
      .controlSize(.small)
      .fixedSize()
      .help(help)
    }
  }

  private var icon: String {
    switch session.suggestedSync {
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
      Image(systemName: session.isGeneratingMessage ? "stop.circle" : "sparkles")
        .symbolEffect(.pulse, isActive: session.isGeneratingMessage)
    }
    .buttonStyle(.borderless)
    .help(help)
  }

  private var help: String {
    if session.isGeneratingMessage { return "Stop writing" }
    guard settings.isReady, let model = settings.modelID else { return settings.setupHint }
    return "Write the message with \(model) on \(settings.provider.name) (⌥⌘G). Sends your diff there."
  }
}
