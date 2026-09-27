import Foundation

/// One commit as shown in the commit list. Plain value type: the git layer
/// builds these, views only read them.
struct Commit: Identifiable, Hashable, Sendable {
  /// Full hex object id.
  let id: String
  let summary: String
  let authorName: String
  let date: Date

  var shortID: String { String(id.prefix(7)) }
}

/// The repository as a whole: where it is and what is checked out.
struct RepositoryInfo: Equatable, Sendable {
  let url: URL
  /// Current branch name, or nil when HEAD is detached or unborn.
  let branch: String?
  /// True when HEAD points at a branch with no commits yet.
  let isEmpty: Bool

  var name: String { url.lastPathComponent }
}
