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
          commit: session.commits.first { $0.id == diff.commitID },
          diff: diff, isLoading: session.isLoadingDiff)
        Divider()
        if diff.files.isEmpty {
          ContentUnavailableView(
            "No changes", systemImage: "doc",
            description: Text("This commit doesn't change any files."))
        } else {
          DiffScrollView(session: session, commitID: diff.commitID)
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

private struct DiffScrollView: View {
  @Bindable var session: RepositorySession
  let commitID: String

  var body: some View {
    let gutterWidth = DiffStyle.gutterWidth(digits: session.lineNumberDigits)
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(session.rows) { row in
            DiffRowView(row: row, gutterWidth: gutterWidth, toggleCollapsed: session.toggleCollapsed)
          }
        }
        .scrollTargetLayout()
      }
      .onScrollTargetVisibilityChange(idType: DiffRowID.self) { visible in
        session.visibleRowsChanged(visible)
      }
      .onChange(of: session.scrollRequest) { _, request in
        guard let request else { return }
        proxy.scrollTo(request.target, anchor: .top)
      }
    }
    .onAppear { session.diffDidAppear(commitID) }
    // A new commit gets a new scroll view, which starts at the top. The id
    // comes after onAppear so it fires once per commit, not once ever.
    .id(commitID)
  }
}

private struct CommitHeader: View {
  let commit: Commit?
  let diff: CommitDiff
  let isLoading: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(commit?.summary ?? diff.commitID)
          .font(.headline)
          .lineLimit(2)
          .textSelection(.enabled)
        Spacer(minLength: 12)
        if isLoading {
          ProgressView().controlSize(.small)
        }
      }
      HStack(spacing: 12) {
        Text(String(diff.commitID.prefix(10)))
          .font(DiffStyle.font)
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
