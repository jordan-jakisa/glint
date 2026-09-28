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
    case .push: sync.upstream == nil ? "Publish Branch" : "Push \(sync.ahead)"
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

  func fetch() {
    runNetwork(.fetch, ["fetch", "--prune"] + (chosenRemote.map { [$0] } ?? []))
  }

  func pull() { runNetwork(.pull, ["pull", "--no-edit"] + remoteAndBranch) }

  /// Zed's Pull (Rebase): replays your commits on top of the remote's.
  func pullRebase() { runNetwork(.pull, ["pull", "--rebase"] + remoteAndBranch) }

  /// Zed's Force Push, made safe: refuses if the remote has work you
  /// haven't fetched.
  func forcePush() {
    guard sync.upstream != nil || chosenRemote != nil else { return push() }
    runNetwork(.push, ["push", "--force-with-lease"] + remoteAndBranch)
  }

  /// With several remotes, the one you picked in the sync menu; nil means
  /// git's own choice (the upstream).
  var chosenRemote: String? {
    guard remotes.count > 1, let remote = selectedRemote, remotes.contains(remote) else { return nil }
    return remote
  }

  /// Git's arguments for the picked remote and the current branch.
  private var remoteAndBranch: [String] {
    guard let remote = chosenRemote, let branch = info?.branch else { return [] }
    return [remote, branch]
  }

  /// Zed shows a remote picker when there's more than one remote.
  func loadRemotes() {
    guard let repository else { return }
    let git = SystemGit(directory: repository.url)
    Task {
      let output = (try? await git.run(["remote"])) ?? ""
      remotes = output.split(separator: "\n").map(String.init)
    }
  }

  /// Pushes, or publishes the branch when it has no upstream yet.
  func push() {
    guard let repository else { return }
    guard sync.upstream == nil || chosenRemote != nil else {
      runNetwork(.push, ["push"])
      return
    }
    if let remote = chosenRemote, let branch = info?.branch {
      runNetwork(.push, ["push", "--set-upstream", remote, branch])
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
    syncOutcome = nil
    let (ahead, behind) = (sync.ahead, sync.behind)
    Task {
      defer { networkOperation = nil }
      do {
        _ = try await git.run(arguments)
        let outcome: SyncOutcome =
          switch operation {
          case .fetch: .fetched
          case .pull: .pulled(behind)
          case .push: .pushed(ahead)
          }
        acknowledge { $0.syncOutcome = outcome } until: { $0.syncOutcome = nil }
      } catch {
        var failed = UserAlert("Couldn't \(operation.verb)", error: error)
        failed.canRetry = true
        retryAlertAction = { [weak self] in self?.runNetwork(operation, arguments) }
        alert = failed
      }
      refresh()
    }
  }

  /// Shows a small acknowledgement for two seconds, then takes it away.
  func acknowledge(_ show: (RepositorySession) -> Void, until hide: @escaping (RepositorySession) -> Void) {
    show(self)
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      if let self { hide(self) }
    }
  }
}
