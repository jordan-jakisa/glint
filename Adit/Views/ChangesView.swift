import SwiftUI

/// Uncommitted work: staged files, then everything else.
struct ChangesView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    VStack(spacing: 0) {
      if session.status.isClean {
        ContentUnavailableView(
          "No changes to commit", systemImage: "checkmark.circle",
          description: Text("Edit a file and it shows up here."))
      } else {
        list
      }
    }
  }

  private var list: some View {
    ScrollViewReader { proxy in
      List(selection: $session.selectedChange) {
        if !session.status.staged.isEmpty {
          Section {
            ForEach(session.status.staged) { file in
              ChangeRow(file: file).tag(ChangeSelection(staged: true, path: file.path))
            }
          } header: {
            GroupHeader(title: "Staged", count: session.status.staged.count) {
              session.selectedChange = ChangeSelection(staged: true, path: nil)
            }
          }
        }
        if !session.status.unstaged.isEmpty {
          Section {
            ForEach(session.status.unstaged) { file in
              ChangeRow(file: file).tag(ChangeSelection(staged: false, path: file.path))
            }
          } header: {
            GroupHeader(title: "Changes", count: session.status.unstaged.count) {
              session.selectedChange = ChangeSelection(staged: false, path: nil)
            }
          }
        }
      }
      .onChange(of: session.selectedChange) { _, selection in
        if let selection, selection.path != nil { proxy.scrollTo(selection) }
      }
    }
  }
}

private struct GroupHeader: View {
  let title: String
  let count: Int
  let viewAll: () -> Void

  var body: some View {
    HStack {
      Text("\(title) \(count)")
      Spacer()
      Button("View All", action: viewAll)
        .buttonStyle(.link)
        .font(.caption)
    }
  }
}

struct ChangeRow: View {
  let file: ChangedFile

  var body: some View {
    HStack(spacing: 6) {
      ChangeKindBadge(kind: file.kind)
      Text(file.fileName)
        .lineLimit(1)
      Text(file.directory)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.head)
      Spacer(minLength: 0)
    }
    .help(file.path)
  }
}

struct ChangeKindBadge: View {
  let kind: ChangedFile.Kind

  var body: some View {
    Text(letter)
      .font(.system(size: 10, weight: .bold, design: .monospaced))
      .foregroundStyle(color)
      .frame(width: 14)
      .help(label)
  }

  private var letter: String {
    switch kind {
    case .added: "A"
    case .modified: "M"
    case .deleted: "D"
    case .renamed: "R"
    case .typeChanged: "T"
    case .untracked: "U"
    case .conflicted: "!"
    }
  }

  private var label: String {
    switch kind {
    case .added: "Added"
    case .modified: "Modified"
    case .deleted: "Deleted"
    case .renamed: "Renamed"
    case .typeChanged: "Type changed"
    case .untracked: "Untracked"
    case .conflicted: "Conflicted"
    }
  }

  private var color: Color {
    switch kind {
    case .added, .untracked: .green
    case .modified, .typeChanged: .orange
    case .deleted, .conflicted: .red
    case .renamed: .blue
    }
  }
}
