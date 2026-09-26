import Foundation

/// An alert that says what happened and what to do next. Git's or the
/// network's own text goes in `details`, one click away, never in the message.
struct UserAlert: Equatable, Sendable {
  var title: String
  var message: String
  var details: String?
  /// Setup hints (AI not configured) offer Settings instead of just OK.
  var opensSettings = false

  /// `title` says what failed ("Couldn't push"); the message comes from the
  /// error, in plain words.
  @MainActor init(_ title: String, error: Error) {
    self.title = title
    let raw = Self.rawText(of: error)
    message = Self.advice(for: error, raw: raw)
    details = raw == message ? nil : raw
  }

  init(_ title: String, message: String, opensSettings: Bool = false) {
    self.title = title
    self.message = message
    self.opensSettings = opensSettings
  }

  private static func rawText(of error: Error) -> String {
    switch error {
    case let error as GitError: [error.message, error.detail].compactMap { $0 }.joined(separator: "\n\n")
    default: "\(error)"
    }
  }

  @MainActor private static func advice(for error: Error, raw: String) -> String {
    switch error {
    case let error as SystemGit.Failure: advice(forGit: error.message)
    case let error as URLError: advice(for: error)
    case let error as GitError: error.message
    case let error as CocoaError where error.code == .fileWriteNoPermission:
      "Adit doesn't have permission to change that file. Check its permissions in Finder, then try again."
    default: raw
    }
  }

  /// Plain words for git's most common failures. Anything else shows git's
  /// first real line, with the rest in the details.
  @MainActor static func advice(forGit text: String) -> String {
    let lower = text.lowercased()
    let terminal = AppCommand.showTerminal.keys
    let inTerminal = terminal.isEmpty ? "in the terminal" : "in the terminal (\(terminal))"
    func has(_ needles: String...) -> Bool { needles.contains { lower.contains($0) } }

    if has("[rejected]", "failed to push some refs"), has("fetch first", "non-fast-forward", "behind") {
      return "The remote has commits you don't have. Pull, then push again."
    }
    if has(
      "authentication failed", "could not read username", "could not read password",
      "permission denied (publickey)", "terminal prompts disabled", "invalid username or password")
    {
      return "Git couldn't sign in to the remote. Run the same command once \(inTerminal) so git saves your login, then try again here."
    }
    if has(
      "could not resolve host", "network is unreachable", "connection timed out", "operation timed out",
      "connection refused", "could not connect to server")
    {
      return "Couldn't reach the remote. Check your connection and try again."
    }
    if has("repository not found", "does not appear to be a git repository") {
      return "The remote isn't there, or you don't have access to it. Check the remote's URL with git remote -v \(inTerminal)."
    }
    if has("unmerged files", "resolve your current index first", "fix conflicts", "conflict (") {
      return "Some files have conflicts. Fix the ones marked !, stage them, then commit."
    }
    if has("index.lock") {
      return "Another git process is using this repository. Try again in a moment."
    }
    if has("would be overwritten by") {
      return "That would overwrite changes you haven't committed. Commit or stash them first, then try again."
    }
    if has("no tracking information") {
      return "This branch doesn't track a remote branch yet. Push it to publish it."
    }
    if has("divergent branches", "not possible to fast-forward", "need to specify how to reconcile") {
      return "Your branch and the remote have both moved on. Run git pull --rebase or git pull --no-rebase \(inTerminal) to choose how to combine them."
    }
    if has("please tell me who you are", "author identity unknown") {
      return "Git doesn't know your name and email yet. Set them with git config --global user.name and user.email \(inTerminal)."
    }
    if has("gpg failed", "error: gpg", "failed to sign") {
      return "Git couldn't sign the commit. Check your signing setup \(inTerminal), then try again."
    }
    return firstLine(of: text).map { "Git said: \($0)" } ?? "Git stopped without saying why. Try the same thing \(inTerminal) to see more."
  }

  private static func advice(for error: URLError) -> String {
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
      "You look offline. Connect and try again."
    case .timedOut:
      "The request took too long. Try again in a moment."
    case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
      "Couldn't reach the server. Check your connection and try again."
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
      "Couldn't make a secure connection. Check your network, or try again on another one."
    default:
      "Something went wrong on the network. Try again in a moment."
    }
  }

  /// Git's first line that isn't a hint, without its "error:" or "fatal:"
  /// prefix.
  private static func firstLine(of text: String) -> String? {
    for line in text.components(separatedBy: .newlines) {
      var trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("hint:") { continue }
      for prefix in ["error: ", "fatal: ", "remote: "] where trimmed.hasPrefix(prefix) {
        trimmed = String(trimmed.dropFirst(prefix.count))
      }
      if !trimmed.isEmpty {
        return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
      }
    }
    return nil
  }
}
