import Foundation

/// The commit box: committing, amending, and undoing the last commit.
extension RepositorySession {
  /// The last commit, shown under the commit box.
  var lastCommit: Commit? { commits.first }

  /// With nothing staged, Commit takes every change to tracked files, like
  /// `git commit -a`. New files still need staging first.
  var commitsTrackedChanges: Bool {
    status.staged.isEmpty && status.unstaged.contains { $0.kind != .untracked && $0.kind != .conflicted }
  }

  var canCommit: Bool {
    guard !isCommitting, !commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return false
    }
    return isAmending || !status.staged.isEmpty || commitsTrackedChanges
  }

  var commitButtonTitle: String {
    if isAmending { return "Amend" }
    return commitsTrackedChanges ? "Commit Tracked" : "Commit"
  }

  /// Remeasures what Commit would take. Runs after every status change;
  /// cheap, since it counts lines without building patches.
  func refreshCommitSize() {
    guard let repository else { return }
    let trackedOnly = commitsTrackedChanges
    guard !status.staged.isEmpty || trackedOnly else {
      commitSize = nil
      return
    }
    Task {
      commitSize = try? await repository.commitSize(trackedOnly: trackedOnly)
    }
  }

  /// Commits with system git, so hooks and signing run like in the terminal.
  func commit() {
    guard canCommit, let repository else { return }
    var arguments = ["commit", "--cleanup=strip", "-F", "-"]
    if isAmending { arguments.append("--amend") }
    if !isAmending, commitsTrackedChanges { arguments.append("-a") }
    let message = commitMessage
    let git = SystemGit(directory: repository.url)
    isCommitting = true
    Timing.writes.notice("commit\(self.isAmending ? " --amend" : "", privacy: .public)")
    Task {
      let start = ContinuousClock.now
      defer { isCommitting = false }
      do {
        _ = try await git.run(arguments, input: message)
        Timing.report("commit", since: start, budget: 100)
        if let generated = generatedMessage {
          let ratio = CommitPrompt.editRatio(from: generated, to: message)
          Timing.log.info("AI message edited before commit: \(Int(ratio * 100))% changed")
          generatedMessage = nil
        }
        commitMessage = ""
        // Done typing: hand the keys back to j, k and Space.
        messageFocusRequest = false
        aiNote = nil
        isAmending = false
      } catch {
        alert = UserAlert("The commit didn't go through", error: error)
      }
      refresh()
    }
  }

  /// Un-commits the last commit, keeping its changes staged and putting its
  /// message back in the box so you can fix it and commit again.
  func undoLastCommit() {
    guard let repository else { return }
    Timing.writes.notice("undo last commit")
    Task {
      do {
        let message = try await repository.undoLastCommit()
        if commitMessage.isEmpty {
          commitMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        }
      } catch {
        alert = UserAlert("Couldn't undo the last commit", error: error)
      }
      refresh()
    }
  }

  func prefillAmendMessage() {
    guard commitMessage.isEmpty, let repository else { return }
    Task {
      guard let message = await repository.headMessage(), isAmending, commitMessage.isEmpty else { return }
      commitMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
  }
}
