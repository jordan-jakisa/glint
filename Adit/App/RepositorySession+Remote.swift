import Foundation

/// Fetch, pull, and push, all through system git so SSH keys, the agent,
/// credential helpers, and pre-push hooks work like they do in the terminal.
extension RepositorySession {
  /// The one-click action the branch bar offers: whatever you most likely
  /// want next.
  var suggestedSync: NetworkOperation {
    if sync.behind > 0 { return .pull }
    if sync.ahead > 0 || (sync.upstream == nil && sync.hasRemotes && info?.branch != nil) { return .push }
    return .fetch
  }

  var suggestedSyncTitle: String {
    switch suggestedSync {
    case .pull: "Pull \(sync.behind)"
    case .push: sync.upstream == nil ? "Publish" : "Push \(sync.ahead)"
    case .fetch: "Fetch"
    }
  }

  func runSuggestedSync() {
    switch suggestedSync {
    case .fetch: fetch()
    case .pull: pull()
    case .push: push()
    }
  }

  func fetch() { runNetwork(.fetch, ["fetch", "--prune"]) }

  func pull() { runNetwork(.pull, ["pull", "--no-edit"]) }

  /// Pushes, or publishes the branch when it has no upstream yet.
  func push() {
    guard let repository else { return }
    guard sync.upstream == nil else {
      runNetwork(.push, ["push"])
      return
    }
    guard let branch = info?.branch else {
      alert = UserAlert("Nothing to push", message: "You're not on a branch. Switch to one first (\(AppCommand.switchBranch.keys)).")
      return
    }
    Task {
      guard let remote = await repository.defaultRemote() else {
        alert = UserAlert(
          "No remote to push to",
          message: "This repository has no remote, or several and none called origin. Add one with git remote add origin <url> in the terminal (\(AppCommand.showTerminal.keys)).")
        return
      }
      runNetwork(.push, ["push", "--set-upstream", remote, branch])
    }
  }

  private func runNetwork(_ operation: NetworkOperation, _ arguments: [String]) {
    guard let repository, networkOperation == nil else { return }
    Timing.writes.notice("git \(arguments.joined(separator: " "), privacy: .public)")
    let git = SystemGit(directory: repository.url)
    networkOperation = operation
    Task {
      defer { networkOperation = nil }
      do {
        _ = try await git.run(arguments)
      } catch {
        alert = UserAlert("Couldn't \(operation.verb)", error: error)
      }
      refresh()
    }
  }
}
