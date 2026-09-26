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

/// `repo / branch`. The branch picker and sync buttons arrive in later steps.
struct BranchBar: View {
  @Bindable var session: RepositorySession

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "arrow.triangle.branch")
        .foregroundStyle(.secondary)
      Text(session.info?.name ?? "")
        .foregroundStyle(.secondary)
      Text("/").foregroundStyle(.tertiary)
      Text(session.info?.branch ?? "detached HEAD")
        .lineLimit(1)
      Spacer()
    }
    .font(.callout)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }
}
