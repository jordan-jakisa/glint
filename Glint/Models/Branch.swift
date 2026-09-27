import Foundation

struct Branch: Identifiable, Hashable, Sendable {
  /// Short name: `main`, or `origin/main` for a remote branch.
  let name: String
  let isRemote: Bool
  let isCurrent: Bool
  /// When its tip commit was made, for sorting by recency.
  let date: Date

  var id: String { (isRemote ? "remote:" : "local:") + name }

  /// What to pass to `git switch`. A remote branch switches by its short name,
  /// which makes git create a local branch that tracks it.
  var switchName: String {
    guard isRemote, let slash = name.firstIndex(of: "/") else { return name }
    return String(name[name.index(after: slash)...])
  }
}

/// The current branch against the branch it was made from.
struct BranchComparison: Equatable, Sendable {
  /// `main`, `origin/main`, or whichever base was found.
  let base: String
  let branch: String?
  /// Commits on this branch that the base doesn't have.
  let ahead: Int
  let mergeBase: String
}

/// Where the current branch stands against its upstream.
struct SyncStatus: Equatable, Sendable {
  /// `origin/main`, or nil when the branch doesn't track anything.
  let upstream: String?
  let ahead: Int
  let behind: Int
  /// Whether the repository has any remote to push to at all.
  let hasRemotes: Bool

  static let none = SyncStatus(upstream: nil, ahead: 0, behind: 0, hasRemotes: false)
}
