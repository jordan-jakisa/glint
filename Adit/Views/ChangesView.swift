import SwiftUI

/// Uncommitted work: staged files, then everything else.
struct ChangesView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      if session.status.isClean {
        ContentUnavailableView(
          "No changes to commit", systemImage: "checkmark.circle",
          description: Text("Edit a file and it shows up here."))
          .frame(maxHeight: .infinity)
      } else {
        list
      }
      CommitPanel(session: session)
    }
  }

  private var toolbar: some View {
    HStack(spacing: 8) {
      Button {
        session.selectedChange = ChangeSelection(staged: session.status.unstaged.isEmpty, path: nil)
      } label: {
        Label("View All", systemImage: "plusminus")
      }
      .buttonStyle(.borderless)
      .disabled(session.status.isClean)
      .help("Show every change in one diff")
      Spacer()
      Menu {
        Button("Stage All", action: session.stageAll)
          .disabled(session.status.unstaged.isEmpty)
        Button("Unstage All", action: session.unstageAll)
          .disabled(session.status.staged.isEmpty)
        Divider()
        Button("Discard All Changes…", action: session.requestDiscardAll)
          .disabled(session.status.unstaged.isEmpty)
      } label: {
        Text(session.status.unstaged.isEmpty && !session.status.staged.isEmpty ? "Unstage All" : "Stage All")
      } primaryAction: {
        if session.status.unstaged.isEmpty { session.unstageAll() } else { session.stageAll() }
      }
      .menuStyle(.borderedButton)
      .fixedSize()
      .disabled(session.status.isClean)
    }
    .controlSize(.small)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }

  private var list: some View {
    ScrollViewReader { proxy in
      List(selection: $session.selectedChange) {
        if !session.status.staged.isEmpty {
          Section {
            ForEach(session.status.staged) { file in
              row(file, staged: true)
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
              row(file, staged: false)
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

  private func row(_ file: ChangedFile, staged: Bool) -> some View {
    ChangeRow(file: file, staged: staged) { session.setStaged(file.path, $0) }
      .tag(ChangeSelection(staged: staged, path: file.path))
      .contextMenu {
        Button(staged ? "Unstage" : "Stage") { session.setStaged(file.path, !staged) }
        if !staged, file.kind != .conflicted {
          Button("Discard Changes…") { session.requestDiscard([file.path]) }
        }
        Divider()
        Button("Reveal in Finder") { session.revealInFinder(file.path) }
        Button("Copy Path") { session.copyPath(file.path) }
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
  let staged: Bool
  let setStaged: (Bool) -> Void

  var body: some View {
    HStack(spacing: 6) {
      Toggle("Staged", isOn: Binding(get: { staged }, set: setStaged))
        .toggleStyle(.checkbox)
        .labelsHidden()
        .help(staged ? "Unstage (Space)" : "Stage (Space)")
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
