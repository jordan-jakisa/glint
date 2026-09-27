import Foundation

/// A plain folder holding several repositories side by side, like a project
/// with its frontend and backend in separate repositories.
struct Workspace: Equatable, Sendable {
  let root: URL
  let repositories: [WorkspaceRepository]

  var name: String { root.lastPathComponent }
}

struct WorkspaceRepository: Identifiable, Hashable, Sendable {
  let url: URL
  /// Path from the workspace folder: `ai-thesis-coach`, or `apps/web`.
  let relativePath: String

  var id: String { relativePath }
  var name: String { url.lastPathComponent }
}

/// How one repository in a workspace stands, for the repository picker.
struct RepositorySummary: Equatable, Sendable {
  let branch: String?
  let status: WorkingTreeStatus

  /// Files with changes, counting a partly staged file once.
  var changeCount: Int {
    Set(status.staged.map(\.path) + status.unstaged.map(\.path)).count
  }
}
