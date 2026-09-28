import SwiftUI

/// Uncommitted work: staged files, then everything else.
struct ChangesView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    VStack(spacing: 0) {
      if session.status.isClean && session.otherRepositoryChanges.isEmpty {
        // The diff pane says where things stand; this only says why it's empty.
        Text("No changes. Edit a file and it shows up here.")
          .font(.app(.callout))
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        list
      }
      CommitPanel(session: session)
    }
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
            GroupHeader(title: groupTitle("Staged"), count: session.status.staged.count) {
              session.selectedChange = ChangeSelection(staged: true, path: nil)
            }
            .contextMenu { Button("Unstage All", action: session.unstageAll) }
          }
        }
        if !session.status.unstaged.isEmpty {
          Section {
            ForEach(session.status.unstaged) { file in
              row(file, staged: false)
            }
          } header: {
            // Stage All lives on the View All diff and in the menu bar;
            // Discard All is here for the mouse.
            GroupHeader(title: groupTitle("Changes"), count: session.status.unstaged.count) {
              session.selectedChange = ChangeSelection(staged: false, path: nil)
            }
            .contextMenu {
              Button("Stage All", action: session.stageAll)
              Button("Discard All Changes…", action: session.requestDiscardAll)
            }
          }
        }
        // Other repositories, read-only here: picking a file switches to its
        // repository and opens it there.
        ForEach(session.otherRepositoryChanges, id: \.repository.id) { group in
          Section {
            ForEach(group.files, id: \.self) { file in
              Button {
                session.switchRepository(to: group.repository, selecting: file)
              } label: {
                OtherRepositoryRow(path: file.path ?? "", kind: group.kinds[file.path ?? ""] ?? .modified)
              }
              .buttonStyle(.plain)
            }
          } header: {
            HStack {
              Text("\(group.repository.relativePath) \(group.files.count)")
                .font(.app(.caption))
              Spacer()
              Button("Switch") { session.switchRepository(to: group.repository) }
                .buttonStyle(.link)
                .font(.app(.caption))
            }
          }
        }
      }
      .environment(\.defaultMinListRowHeight, Theme.shared.isMinimal ? 20 : 24)
      .onChange(of: session.selectedChange) { _, selection in
        if let selection, selection.path != nil { proxy.scrollTo(selection) }
      }
    }
  }

  /// In the all-repositories view, the active repository's groups say whose
  /// they are.
  private func groupTitle(_ group: String) -> String {
    guard session.showsAllRepositories, session.workspace != nil, let name = session.info?.name else { return group }
    return "\(name) \u{00B7} \(group)"
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
        // Links point at your last commit, which a new file isn't in yet.
        if file.kind != .added, file.kind != .untracked {
          Divider()
          Button("Copy File Permalink") { session.copyFilePermalink(file.path) }
          Button("Open File Permalink") { session.openFilePermalink(file.path) }
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
      // Minimal drops the link; the header itself shows every file.
      if !Theme.shared.isMinimal {
        Button("View All", action: viewAll)
          .buttonStyle(.link)
          .font(.app(.caption))
      }
    }
    .font(.app(.caption))
    .contentShape(Rectangle())
    .onTapGesture(perform: viewAll)
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
        .help(AppCommand.toggleStaged.hint(staged ? "Unstage" : "Stage"))
      ChangeKindBadge(kind: file.kind)
      Text(file.fileName)
        .lineLimit(1)
      Text(file.directory)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.head)
      Spacer(minLength: 0)
    }
    // Lists set their own font; set the app's closer in.
    .font(.app(.body))
    .help(file.path)
  }
}

/// A changed file in a repository that isn't the active one.
private struct OtherRepositoryRow: View {
  let path: String
  let kind: ChangedFile.Kind

  var body: some View {
    HStack(spacing: 6) {
      Color.clear.frame(width: 16)
      ChangeKindBadge(kind: kind)
      Text((path as NSString).lastPathComponent)
        .lineLimit(1)
      Text((path as NSString).deletingLastPathComponent)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.head)
      Spacer(minLength: 0)
    }
    .foregroundStyle(.secondary)
    .font(.app(.body))
    .contentShape(Rectangle())
    .help("Switch to this repository and open \(path)")
  }
}
