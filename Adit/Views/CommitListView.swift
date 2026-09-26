import SwiftUI

struct CommitListView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    ScrollViewReader { proxy in
      List(selection: $session.selectedCommitID) {
        ForEach(session.commits) { commit in
          CommitRow(commit: commit)
            .onAppear {
              // History is read in pages. The last row coming on screen asks
              // for the next one.
              if commit.id == session.commits.last?.id { session.loadMoreCommits() }
            }
        }
      }
      .onChange(of: session.selectedCommitID) { _, id in
        if let id { proxy.scrollTo(id) }
      }
    }
    .overlay {
      if session.commits.isEmpty {
        ContentUnavailableView(
          "No commits yet", systemImage: "circle.dashed",
          description: Text("Commit something and it shows up here."))
      }
    }
    .onAppear {
      if !session.commits.isEmpty { Timing.reportLaunchIfNeeded() }
    }
  }
}

private struct CommitRow: View {
  let commit: Commit

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(commit.summary)
        .lineLimit(1)
      HStack(spacing: 6) {
        Text(commit.shortID)
          .font(.system(size: 11, design: .monospaced))
        Text(commit.authorName)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text(RelativeDate.string(for: commit.date))
          .lineLimit(1)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}

/// "3 hours ago". One shared formatter: making one per row is measurably slow.
@MainActor
private enum RelativeDate {
  private static let formatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter
  }()

  static func string(for date: Date) -> String {
    formatter.localizedString(for: date, relativeTo: .now)
  }
}
