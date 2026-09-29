import Foundation

/// One of a repository's working trees: the main checkout, or a linked one
/// made with `git worktree add`.
struct Worktree: Identifiable, Hashable, Sendable {
  let url: URL
  /// Short branch name, or nil when the worktree is on a detached HEAD.
  let branch: String?
  /// The repository's own checkout, which can't be removed.
  let isMain: Bool

  var id: String { url.path }
  var name: String { url.lastPathComponent }

  /// Reads `git worktree list --porcelain`: blocks separated by blank lines,
  /// the main worktree first. Bare entries have no files to open and are
  /// skipped.
  static func parse(porcelain: String) -> [Worktree] {
    var result: [Worktree] = []
    for block in porcelain.components(separatedBy: "\n\n") {
      var path: String?
      var branch: String?
      var isBare = false
      for line in block.split(separator: "\n") {
        if line.hasPrefix("worktree ") {
          path = String(line.dropFirst("worktree ".count))
        } else if line.hasPrefix("branch ") {
          let ref = line.dropFirst("branch ".count)
          branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : String(ref)
        } else if line == "bare" {
          isBare = true
        }
      }
      guard let path, !isBare else { continue }
      result.append(Worktree(url: URL(fileURLWithPath: path), branch: branch, isMain: result.isEmpty))
    }
    return result
  }
}
