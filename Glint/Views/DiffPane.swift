import SwiftUI

/// The right-hand side: the selected commit's header and its diff.
struct DiffPane: View {
  @Bindable var session: RepositorySession

  var body: some View {
    // A conflicted file shows its conflicts to resolve, not a diff.
    if let path = session.selectedConflictPath {
      ConflictView(session: session, path: path)
    } else if let error = session.diffError {
      // Minimal shows no title, so the description says what failed.
      EmptyState(
        "Couldn't load this diff", systemImage: "exclamationmark.triangle",
        description: Text(Theme.shared.isMinimal ? "Couldn't load this diff. \(error)" : error))
    } else if let diff = session.diff {
      VStack(spacing: 0) {
        header(for: diff)
        Hairline()
        if diff.files.isEmpty {
          EmptyState(
            "No changes", systemImage: "doc",
            description: Text(emptyDescription(for: diff.source)))
        } else {
          DiffTableView(
            rows: session.rows, rowsVersion: session.rowsVersion, rowsChange: session.rowsChange,
            source: diff.source,
            lineNumberDigits: session.lineNumberDigits, textSize: TextSize.shared.body,
            themeVersion: Theme.shared.version,
            scroller: session.diffScroller,
            toggleCollapsed: session.toggleCollapsed,
            visibleRowsChanged: session.visibleRowsChanged,
            didPaint: session.diffDidAppear,
            partialAction: session.partialAction,
            selectionChanged: session.lineSelectionChanged,
            hunkAction: session.stageHunk,
            editLines: editLines)
        }
      }
    } else if session.tab == .changes, session.status.isClean {
      CaughtUpView(session: session)
    } else if session.tab == .changes {
      EmptyState(
        "Pick a file", systemImage: "doc.text",
        description: Text(
          "Press \(AppCommand.nextItem.keys) to start. \(AppCommand.toggleStaged.keys) stages a file, "
            + "\(AppCommand.stagePartial.keys) stages a hunk."))
    } else if session.selectedCommitID == nil {
      EmptyState(
        "Pick a commit", systemImage: "list.bullet",
        description: Text("Choose one on the left, or press \(AppCommand.nextItem.keys)."))
    } else {
      // First load for this window. It lands within a frame or two, so show
      // nothing rather than a spinner that would only flicker.
      Color.clear
    }
  }

  /// Edits go to your working copy, so only its diff offers them.
  private var editLines: ((DiffRowID) -> Void)? {
    guard session.canEditDiff else { return nil }
    let session = session
    return { session.beginEdit($0) }
  }

  @ViewBuilder private func header(for diff: Diff) -> some View {
    switch diff.source {
    case .commit(let id):
      CommitHeader(
        commit: session.commits.first { $0.id == id },
        diff: diff, isLoading: session.isLoadingDiff)
    case .branch:
      BranchHeader(comparison: session.branchComparison, diff: diff, isLoading: session.isLoadingDiff)
    case .workingTree(let staged, let path):
      WorkingTreeHeader(
        staged: staged, path: path, diff: diff, isLoading: session.isLoadingDiff,
        selectedLines: session.selectedLineRows.count, stageLines: session.stageSelectedLines
      ) {
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
    case .workingTree(true, _): "Nothing staged here. Press \(AppCommand.toggleStaged.keys) on a file to stage it."
    case .workingTree(false, _): "Nothing changed here."
    case .branch: "This branch doesn't change anything yet."
    }
  }
}

/// A clean working tree: what's left to do with the remote, if anything.
private struct CaughtUpView: View {
  let session: RepositorySession

  var body: some View {
    let sync = session.sync
    if sync.behind > 0 {
      EmptyState {
        Label(commits(sync.behind) + " to pull", systemImage: "arrow.down.circle")
      } description: {
        Text("Everything here is committed. \(sync.upstream ?? "The remote") has new work.")
      } actions: {
        Button("Pull", action: session.pull)
      }
    } else if sync.ahead > 0 {
      EmptyState {
        Label(commits(sync.ahead) + " to push", systemImage: "arrow.up.circle")
      } description: {
        Text("Everything's committed. Push when you're ready.")
      } actions: {
        Button("Push", action: session.push)
      }
    } else if sync.upstream == nil, sync.hasRemotes, session.info?.branch != nil {
      EmptyState {
        Label("Not published yet", systemImage: "arrow.up.circle")
      } description: {
        Text("Everything's committed. Publish the branch to share it.")
      } actions: {
        Button("Publish Branch", action: session.push)
      }
    } else {
      EmptyState(
        "All caught up", systemImage: "checkmark.circle",
        description: Text(sync.upstream == nil ? "Everything's committed." : "Everything's committed and pushed."))
    }
  }

  private func commits(_ count: Int) -> String { count == 1 ? "1 commit" : "\(count) commits" }
}

private struct WorkingTreeHeader: View {
  let staged: Bool
  let path: String?
  let diff: Diff
  let isLoading: Bool
  let selectedLines: Int
  let stageLines: () -> Void
  let toggleStaged: () -> Void

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(path ?? (staged ? "All staged changes" : "All unstaged changes"))
          .font(.app(.headline))
          .lineLimit(1)
          .truncationMode(.head)
          .textSelection(.enabled)
        HStack(spacing: 12) {
          Text(staged ? "Staged" : "Unstaged")
          ChangeStats(additions: diff.additions, deletions: diff.deletions)
        }
        .font(.app(.callout))
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      DelayedSpinner(isActive: isLoading)
      if selectedLines > 0 {
        Button(staged ? "Unstage Lines" : "Stage Lines", action: stageLines)
          .controlSize(.small)
          .help(AppCommand.stagePartial.hint("\(selectedLines) selected"))
      }
      Button(buttonTitle, action: toggleStaged)
        .controlSize(.small)
        .help(AppCommand.toggleStaged.hint(buttonTitle))
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
          .font(.app(.headline))
          .lineLimit(2, reservesSpace: true)
          .textSelection(.enabled)
        Spacer(minLength: 12)
        DelayedSpinner(isActive: isLoading)
      }
      HStack(spacing: 12) {
        Text(String((diff.source.commitID ?? "").prefix(10)))
          .font(.code(.callout))
          .textSelection(.enabled)
        if let commit {
          Text(commit.authorName)
          Text(commit.date, format: .dateTime.day().month().year().hour().minute())
        }
        Spacer(minLength: 12)
        Text(fileCount)
        ChangeStats(additions: diff.additions, deletions: diff.deletions)
      }
      .font(.app(.callout))
      .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var fileCount: String {
    diff.files.count == 1 ? "1 file" : "\(diff.files.count) files"
  }
}

/// Header for the branch diff: which branch, against what, and how far.
private struct BranchHeader: View {
  let comparison: BranchComparison?
  let diff: Diff
  let isLoading: Bool

  var body: some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.app(.headline))
          .lineLimit(1)
        HStack(spacing: 12) {
          if let comparison {
            Text(comparison.ahead == 1 ? "1 commit" : "\(comparison.ahead) commits")
            Text("since \(comparison.mergeBase)")
          }
          Text("plus uncommitted work")
          Text(diff.files.count == 1 ? "1 file" : "\(diff.files.count) files")
          ChangeStats(additions: diff.additions, deletions: diff.deletions)
        }
        .font(.app(.callout))
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
      DelayedSpinner(isActive: isLoading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private var title: String {
    guard let comparison else { return "This branch" }
    return "\(comparison.branch ?? "HEAD") compared with \(comparison.base)"
  }
}
