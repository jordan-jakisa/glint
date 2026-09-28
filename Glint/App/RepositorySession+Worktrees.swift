import Foundation

/// Worktrees as places a branch lives: opening the one a branch is checked
/// out in, making a new one for a branch, and removing one. All through system
/// git, so hooks and config apply like in the terminal.
extension RepositorySession {
  func loadWorktrees() {
    guard let repository else { return }
    let git = SystemGit(directory: repository.url)
    Task {
      // A repository git can't list worktrees for simply has none to show.
      worktrees = (try? await Worktree.parse(porcelain: git.run(["worktree", "list", "--porcelain"]))) ?? []
    }
  }

  /// The other worktree `branch` is checked out in, if any. Git won't switch
  /// to it here, so the picker opens that worktree instead.
  func worktree(for branch: Branch) -> Worktree? {
    guard !branch.isRemote, !branch.isCurrent, let here = repository?.url else { return nil }
    return worktrees.first { $0.branch == branch.name && !Self.isSameFolder($0.url, here) }
  }

  /// The worktrees you could remove from here: linked ones you aren't in.
  var removableWorktrees: [Worktree] {
    guard let here = repository?.url else { return [] }
    return worktrees.filter { !$0.isMain && !Self.isSameFolder($0.url, here) }
  }

  func openWorktree(_ worktree: Worktree) {
    isBranchPickerShown = false
    openProject(worktree.url)
  }

  /// Makes a worktree for `branch` beside the repository and opens it. With
  /// `isNew`, the branch is created there too.
  func createWorktree(branch name: String, isNew: Bool) {
    guard let repository, !isSwitchingBranch else { return }
    let target = newWorktreeURL(for: name)
    let arguments =
      isNew
      ? ["worktree", "add", "-b", name, target.path]
      : ["worktree", "add", target.path, name]
    Timing.writes.notice("worktree add")
    let git = SystemGit(directory: repository.url)
    isSwitchingBranch = true
    Task {
      defer { isSwitchingBranch = false }
      do {
        _ = try await git.run(arguments)
        isBranchPickerShown = false
        openProject(target)
      } catch {
        alert = UserAlert("Couldn't make a worktree for \(name)", error: error)
      }
    }
  }

  func removeWorktree(_ worktree: Worktree) {
    guard let repository, !worktree.isMain else { return }
    Timing.writes.notice("worktree remove")
    let git = SystemGit(directory: repository.url)
    Task {
      do {
        _ = try await git.run(["worktree", "remove", worktree.url.path])
      } catch {
        alert = UserAlert("Couldn't remove the \(worktree.name) worktree", error: error)
      }
      loadWorktrees()
    }
  }

  /// `../worktrees/<repo>-<branch>`, Zed's default worktree folder beside
  /// the main checkout. A number is added if the name is taken.
  private func newWorktreeURL(for branch: String) -> URL {
    let main = worktrees.first(where: \.isMain)?.url ?? repository?.url ?? URL(fileURLWithPath: NSHomeDirectory())
    let base = main.lastPathComponent + "-" + branch.replacingOccurrences(of: "/", with: "-")
    let parent = main.deletingLastPathComponent().appendingPathComponent("worktrees")
    try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    var candidate = parent.appendingPathComponent(base)
    var number = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = parent.appendingPathComponent("\(base)-\(number)")
      number += 1
    }
    return candidate
  }

  private static func isSameFolder(_ a: URL, _ b: URL) -> Bool {
    a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
  }
}
