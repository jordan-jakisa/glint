import Foundation

/// One file with uncommitted changes, in either the staged or the unstaged
/// group. A partly staged file appears in both.
struct ChangedFile: Identifiable, Hashable, Sendable {
  enum Kind: Sendable {
    case added, modified, deleted, renamed, typeChanged
    /// New and never staged.
    case untracked
    /// Unresolved merge conflict. Selecting one shows its conflicts to resolve.
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

extension WorkingTreeStatus {
  /// This status with `paths` replaced by what a status of just those paths
  /// found, for updating after the file watcher reports a few changes.
  func merging(_ partial: WorkingTreeStatus, for paths: Set<String>) -> WorkingTreeStatus {
    let order = FileOrder.current
    return WorkingTreeStatus(
      staged: order.sorted(staged.filter { !paths.contains($0.path) } + partial.staged, path: \.path),
      unstaged: order.sorted(unstaged.filter { !paths.contains($0.path) } + partial.unstaged, path: \.path))
  }

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

/// Lines added and deleted in a file, like `git diff --numstat`.
struct LineStat: Equatable, Sendable {
  let added: Int
  let deleted: Int
}

/// How much of a file is staged: its checkbox in the Changes list.
enum StageState: Sendable { case none, partial, all }

/// One file in the Changes list: staged and unstaged together.
struct StagingEntry: Identifiable, Hashable, Sendable {
  let path: String
  let kind: ChangedFile.Kind
  let state: StageState
  let hasUnstaged: Bool
  var id: String { path }
  var fileName: String { (path as NSString).lastPathComponent }
  var directory: String { (path as NSString).deletingLastPathComponent }
}

extension WorkingTreeStatus {
  /// Each path once, in the File order setting's order, the same as the
  /// diff's. A file only in the staged group is
  /// fully staged; in both, partly; only unstaged, not at all.
  var entries: [StagingEntry] {
    let staged = Dictionary(self.staged.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    let unstaged = Dictionary(self.unstaged.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    return FileOrder.current.sorted(Array(Set(staged.keys).union(unstaged.keys)), path: { $0 }).map { path in
      let state: StageState = unstaged[path] == nil ? .all : (staged[path] == nil ? .none : .partial)
      // A new file with later edits is still new: say so, not "modified".
      let kind =
        staged[path]?.kind == .added && unstaged[path]?.kind != .conflicted
        ? .added : (unstaged[path]?.kind ?? staged[path]!.kind)
      return StagingEntry(path: path, kind: kind, state: state, hasUnstaged: unstaged[path] != nil)
    }
  }
}
