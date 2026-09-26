import Foundation

/// One file with uncommitted changes, in either the staged or the unstaged
/// group. A partly staged file appears in both.
struct ChangedFile: Identifiable, Hashable, Sendable {
  enum Kind: Sendable {
    case added, modified, deleted, renamed, typeChanged
    /// New and never staged.
    case untracked
    /// Unresolved merge conflict. Adit shows these but doesn't resolve them.
    case conflicted
  }

  let path: String
  let kind: Kind

  var id: String { path }

  var fileName: String { (path as NSString).lastPathComponent }

  /// The folder part of the path, or "" at the root.
  var directory: String {
    let directory = (path as NSString).deletingLastPathComponent
    return directory
  }
}

/// How big a commit would be.
struct ChangeSize: Equatable, Sendable {
  let files: Int
  let additions: Int
  let deletions: Int
}

/// What `git status` reports, split the way the Changes tab shows it.
struct WorkingTreeStatus: Equatable, Sendable {
  var staged: [ChangedFile]
  var unstaged: [ChangedFile]

  static let clean = WorkingTreeStatus(staged: [], unstaged: [])

  var isClean: Bool { staged.isEmpty && unstaged.isEmpty }
}

extension WorkingTreeStatus {
  /// What the lists should show right after staging `path`, before git has
  /// confirmed it. The next real status replaces this.
  mutating func markStaged(_ path: String) {
    guard let index = unstaged.firstIndex(where: { $0.path == path }) else { return }
    let file = unstaged.remove(at: index)
    guard !staged.contains(where: { $0.path == path }) else { return }
    let kind: ChangedFile.Kind = file.kind == .untracked ? .added : file.kind
    staged.append(ChangedFile(path: path, kind: kind))
    staged = FileOrder.current.sorted(staged, path: \.path)
  }

  mutating func markUnstaged(_ path: String) {
    guard let index = staged.firstIndex(where: { $0.path == path }) else { return }
    let file = staged.remove(at: index)
    guard !unstaged.contains(where: { $0.path == path }) else { return }
    let kind: ChangedFile.Kind = file.kind == .added ? .untracked : file.kind
    unstaged.append(ChangedFile(path: path, kind: kind))
    unstaged = FileOrder.current.sorted(unstaged, path: \.path)
  }
}
