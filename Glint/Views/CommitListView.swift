import SwiftUI

struct CommitListView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    VStack(spacing: 0) {
      // View File History: which file, and the way back to all history.
      if let path = session.historyPath {
        HStack(spacing: 6) {
          Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
          Text((path as NSString).lastPathComponent).lineLimit(1).truncationMode(.middle)
          Spacer()
          Button {
            session.clearHistoryFilter()
          } label: {
            Image(systemName: "xmark").font(.app(.caption2)).hitTarget()
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Show all history")
          .help("Show all history")
        }
        .font(.app(.callout))
        .padding(.horizontal, 10)
        .frame(height: 30)
        .help(path)
        Hairline()
      }
      list
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      List(selection: $session.selectedCommitID) {
        if session.historyPath == nil, let base = session.branchBaseName {
          BranchRow(branch: session.info?.branch, base: base)
            .tag(RepositorySession.branchSelectionID)
        }
        ForEach(session.visibleCommits) { commit in
          CommitRow(commit: commit)
            .onAppear {
              // History is read in pages. The last row coming on screen asks
              // for the next one.
              if session.historyPath == nil, commit.id == session.commits.last?.id { session.loadMoreCommits() }
            }
        }
      }
      .scrollContentBackground(Theme.shared.isZed ? .hidden : .automatic)
      .environment(\.defaultMinListRowHeight, Theme.shared.isMinimal ? 20 : 24)
      .onChange(of: session.selectedCommitID) { _, id in
        if let id { proxy.scrollTo(id) }
      }
    }
    .overlay {
      if session.visibleCommits.isEmpty, session.historyPath == nil {
        EmptyState(
          "No commits yet", systemImage: "circle.dashed",
          description: Text("Commit something and it shows up here."))
      }
    }
  }
}

private struct CommitRow: View {
  let commit: Commit

  var body: some View {
    if Theme.shared.isZed {
      zedRow
    } else {
      standardRow
    }
  }

  /// Zed's history entry: the summary, then author, age and short id, each
  /// dimmed and separated by dots.
  private var zedRow: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(commit.summary)
        .font(.app(.body))
        .lineLimit(1)
      HStack(spacing: 4) {
        Image(systemName: "person")
        Text(commit.authorName).lineLimit(1)
        Text("\u{2022}")
        Text(RelativeDate.string(for: commit.date)).lineLimit(1)
        Text("\u{2022}")
        Text(commit.shortID).font(.code(.caption))
      }
      .font(.app(.caption))
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }

  private var standardRow: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(commit.summary)
        .font(.app(.body))
        .lineLimit(1)
      HStack(spacing: 6) {
        Text(commit.shortID)
          .font(.code(.caption))
        Text(commit.authorName)
          .lineLimit(1)
        Spacer(minLength: 4)
        Text(RelativeDate.string(for: commit.date))
          .lineLimit(1)
      }
      .font(.app(.caption))
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

/// History's pinned first row: the whole branch, as one diff.
private struct BranchRow: View {
  let branch: String?
  let base: String

  var body: some View {
    // One line; the comparison's detail is in the tooltip.
    // Not a Label: sidebar lists restyle a Label's title in the system font.
    HStack(spacing: 6) {
      Image(systemName: "arrow.triangle.branch").foregroundStyle(.secondary)
      Text("\(branch ?? "This branch") vs \(base)").lineLimit(1)
    }
    .font(.app(.body))
      .padding(.vertical, 2)
      .help("Everything on \(branch ?? "this branch") since it left \(base), uncommitted work included")
  }
}
