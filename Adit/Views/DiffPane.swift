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
        CommitHeader(
          commit: session.commits.first { $0.id == diff.source.commitID },
          diff: diff, isLoading: session.isLoadingDiff)
        Divider()
        if diff.files.isEmpty {
          ContentUnavailableView(
            "No changes", systemImage: "doc",
            description: Text("This commit doesn't change any files."))
        } else {
          DiffTableView(
            rows: session.rows, rowsVersion: session.rowsVersion, source: diff.source,
            lineNumberDigits: session.lineNumberDigits, scroller: session.diffScroller,
            toggleCollapsed: session.toggleCollapsed,
            visibleRowsChanged: session.visibleRowsChanged,
            didPaint: session.diffDidAppear)
        }
      }
    } else if session.selectedCommitID == nil {
      ContentUnavailableView("Pick a commit", systemImage: "list.bullet")
    } else {
      // First load for this window. It lands within a frame or two, so show
      // nothing rather than a spinner that would only flicker.
      Color.clear
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
