import Foundation

/// Writing the commit message with a free hosted model. The diff goes to the
/// provider picked in Settings, never anywhere unless you ask.
extension RepositorySession {
  var isGeneratingMessage: Bool { messageTask != nil }

  func generateCommitMessage() {
    if let messageTask {
      messageTask.cancel()
      self.messageTask = nil
      return
    }
    let settings = AISettings.shared
    guard settings.isReady, let model = settings.modelID else {
      alertMessage = settings.setupHint
      return
    }
    guard let key = settings.readKey() else {
      alertMessage = "Adit couldn't read your \(settings.provider.name) key from the Keychain. Add it again in Settings (⌘,)."
      return
    }
    guard let repository else { return }
    // Like the commit button: staged changes if there are any, else every
    // tracked change.
    let staged = !status.staged.isEmpty
    let subject = commitMessage.components(separatedBy: "\n").first ?? ""
    let client = AIClient(provider: settings.provider, apiKey: key)
    let instructions = settings.instructions
    let followsRules = settings.followsRepositoryRules
    let workspaceRoot = workspace?.root
    Timing.writes.notice("generate commit message with \(settings.provider.rawValue, privacy: .public)/\(model, privacy: .public)")

    messageTask = Task {
      defer { messageTask = nil }
      do {
        let diff = try await repository.workingTreeDiff(staged: staged, path: nil)
        guard !diff.files.isEmpty else {
          alertMessage = "There's nothing to describe yet. Change something first."
          return
        }
        let rules = followsRules ? Self.rules(for: repository.url, workspace: workspaceRoot) : nil
        let prompt = CommitPrompt.build(
          diff: CommitPrompt.compress(CommitPrompt.patchText(diff)), subject: subject,
          rules: rules, userInstructions: instructions)

        var reply = ""
        let start = ContinuousClock.now
        var reportedFirstToken = false
        for try await piece in client.stream(model: model, prompt: prompt) {
          if !reportedFirstToken {
            reportedFirstToken = true
            Timing.report("AI first token", since: start, budget: 2_000)
          }
          reply += piece
          commitMessage = CommitPrompt.clean(reply)
        }
        commitMessage = CommitPrompt.clean(reply)
        if commitMessage.isEmpty {
          alertMessage = "The model sent back an empty message. Try again, or pick another model."
        }
      } catch is CancellationError {
      } catch let error as URLError where error.code == .cancelled {
      } catch {
        alertMessage = "Couldn't write the message.\n\n\(error)"
      }
    }
  }

  /// The repository's rules file, or else the workspace folder's: a project
  /// split across repositories often keeps one AGENTS.md or CLAUDE.md above
  /// them all.
  nonisolated static func rules(for repository: URL, workspace: URL?) -> String? {
    repositoryRules(in: repository) ?? workspace.flatMap { repositoryRules(in: $0) }
  }

  /// The repository's own conventions for agents, from the first rules file
  /// found at its root, capped so it can't crowd out the diff.
  nonisolated static func repositoryRules(in root: URL) -> String? {
    for name in CommitPrompt.rulesFiles {
      let url = root.appendingPathComponent(name)
      guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { return String(trimmed.prefix(6_000)) }
    }
    return nil
  }
}
