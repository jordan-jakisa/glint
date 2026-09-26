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

/// What `git status` reports, split the way the Changes tab shows it.
struct WorkingTreeStatus: Equatable, Sendable {
  var staged: [ChangedFile]
  var unstaged: [ChangedFile]

  static let clean = WorkingTreeStatus(staged: [], unstaged: [])

  var isClean: Bool { staged.isEmpty && unstaged.isEmpty }
}
