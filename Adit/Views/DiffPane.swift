import SwiftUI

/// The right-hand side: the selected commit's header and its diff.
struct DiffPane: View {
  @Bindable var session: RepositorySession

  var body: some View {
    if let error = session.diffError {
      ContentUnavailableView(
        "Couldn't load this diff", systemImage: "exclamationmark.triangle",
        description: Text(error))
    } else if let diff = session.diff {
      VStack(spacing: 0) {
        header(for: diff)
        Divider()
        if diff.files.isEmpty {
          ContentUnavailableView(
            "No changes", systemImage: "doc",
            description: Text(emptyDescription(for: diff.source)))
        } else {
          DiffTableView(
            rows: session.rows, rowsVersion: session.rowsVersion, source: diff.source,
            lineNumberDigits: session.lineNumberDigits, scroller: session.diffScroller,
            toggleCollapsed: session.toggleCollapsed,
            visibleRowsChanged: session.visibleRowsChanged,
            didPaint: session.diffDidAppear)
        }
      }
    } else if session.tab == .changes {
      ContentUnavailableView(
        "No changes to commit", systemImage: "checkmark.circle",
        description: Text("Your working tree matches the last commit."))
    } else if session.selectedCommitID == nil {
      ContentUnavailableView("Pick a commit", systemImage: "list.bullet")
    } else {
      // First load for this window. It lands within a frame or two, so show
      // nothing rather than a spinner that would only flicker.
      Color.clear
    }
  }

  @ViewBuilder private func header(for diff: Diff) -> some View {
    switch diff.source {
    case .commit(let id):
      CommitHeader(
        commit: session.commits.first { $0.id == id },
        diff: diff, isLoading: session.isLoadingDiff)
    case .workingTree(let staged, let path):
      WorkingTreeHeader(staged: staged, path: path, diff: diff, isLoading: session.isLoadingDiff) {
        if let path {
          session.setStaged(path, !staged)
        } else if staged {
          session.unstageAll()
        } else {
          session.stageAll()
        }
      }
    }
  }

  private func emptyDescription(for source: DiffSource) -> String {
    switch source {
    case .commit: "This commit doesn't change any files."
    case .workingTree(true, _): "Nothing staged here."
    case .workingTree(false, _): "Nothing changed here."
    }
  }
}

private struct WorkingTreeHeader: View {
  let staged: Bool
  let path: String?
  let diff: Diff
  let isLoading: Bool
  let toggleStaged: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(path ?? (staged ? "All staged changes" : "All unstaged changes"))
          .font(.headline)
          .lineLimit(1)
          .truncationMode(.head)
          .textSelection(.enabled)
        HStack(spacing: 12) {
          Text(staged ? "Staged" : "Not staged")
          Text("+\(diff.additions)").foregroundStyle(.green)
          Text("-\(diff.deletions)").foregroundStyle(.red)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      if isLoading {
        ProgressView().controlSize(.small)
      }
      Button(buttonTitle, action: toggleStaged)
        .help("Space")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var buttonTitle: String {
    switch (staged, path) {
    case (true, nil): "Unstage All"
    case (false, nil): "Stage All"
    case (true, _): "Unstage File"
    case (false, _): "Stage File"
    }
  }
}

private struct CommitHeader: View {
  let commit: Commit?
  let diff: Diff
  let isLoading: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(commit?.summary ?? "")
          .font(.headline)
          .lineLimit(2)
          .textSelection(.enabled)
        Spacer(minLength: 12)
        if isLoading {
          ProgressView().controlSize(.small)
        }
      }
      HStack(spacing: 12) {
        Text(String((diff.source.commitID ?? "").prefix(10)))
          .font(.system(size: 12, design: .monospaced))
          .textSelection(.enabled)
        if let commit {
          Text(commit.authorName)
          Text(commit.date, format: .dateTime.day().month().year().hour().minute())
        }
        Spacer(minLength: 12)
        Text(fileCount)
        Text("+\(diff.additions)").foregroundStyle(.green)
        Text("-\(diff.deletions)").foregroundStyle(.red)
      }
      .font(.callout)
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var fileCount: String {
    diff.files.count == 1 ? "1 file" : "\(diff.files.count) files"
  }
}
