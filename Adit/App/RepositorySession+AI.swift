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
      alert = UserAlert("Set up AI messages", message: settings.setupHint, opensSettings: true)
      return
    }
    guard let key = settings.readKey() else {
      alert = UserAlert(
        "Couldn't read your key",
        message: "Adit couldn't read your \(settings.provider.name) key from the Keychain. Add it again in Settings.",
        opensSettings: true)
      return
    }
    guard let repository else { return }
    aiNote = nil
    // Like the commit button: staged changes if there are any, else every
    // tracked change.
    let staged = !status.staged.isEmpty
    let lines = commitMessage.components(separatedBy: "\n")
    let subject = lines.first ?? ""
    // Anything typed below the subject is the user's own reason.
    let userWhy = lines.dropFirst().joined(separator: "\n")
    let recentSubjects = commits.prefix(10).map(\.summary)
    let before = commitMessage
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
          alert = UserAlert("Nothing to describe", message: "Change something first, then try again.")
          return
        }
        let rules = followsRules ? Self.rules(for: repository.url, workspace: workspaceRoot) : nil
        let prompt = CommitPrompt.build(
          diff: CommitPrompt.compress(CommitPrompt.patchText(diff)), subject: subject,
          rules: rules, userInstructions: instructions, recentSubjects: recentSubjects, userWhy: userWhy)

        // Free models are often busy. Try the chosen one, then up to two
        // other free ones, and say which wrote the message.
        let candidates = await AISettings.shared.fallbackModels(count: 3)
        var reply = ""
        var usedModel = model
        for (attempt, candidate) in candidates.enumerated() {
          reply = ""
          usedModel = candidate
          do {
            let start = ContinuousClock.now
            var reportedFirstToken = false
            for try await piece in client.stream(model: candidate, prompt: prompt) {
              if !reportedFirstToken {
                reportedFirstToken = true
                Timing.report("AI first token", since: start, budget: 2_000)
              }
              reply += piece
              commitMessage = CommitPrompt.clean(reply)
            }
            break
          } catch let failure as AIClient.Failure where failure.isBusy && attempt < candidates.count - 1 {
            Timing.log.info("AI: \(candidate, privacy: .public) was busy, trying the next free model")
            commitMessage = before
            continue
          }
        }
        let final = CommitPrompt.clean(reply)
        if final.isEmpty || CommitPrompt.isWeak(final) {
          // Weak messages are worse than none: put back what was there.
          commitMessage = before
          alert = UserAlert("No message this time", message: final.isEmpty
            ? "The model sent back an empty message. Try again, or pick another model."
            : "That one wasn't useful (\u{201C}\(final.components(separatedBy: "\n").first ?? final)\u{201D}). Try again, or pick another model.")
        } else {
          commitMessage = final
          generatedMessage = final
          aiNote = usedModel == model
            ? "Written by \(usedModel)"
            : "Written by \(usedModel): \(model) was busy"
        }
      } catch is CancellationError {
      } catch let error as URLError where error.code == .cancelled {
      } catch {
        alert = UserAlert("Couldn't write the message", error: error)
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
