import Foundation

/// One entry of `git stash list`: changes you set aside to get back later.
struct Stash: Identifiable, Hashable, Sendable {
  /// Position in the list, newest first: the n in `stash@{n}`. Shifts as
  /// stashes are made and dropped, so actions find the stash again by `id`.
  let index: Int
  /// The stash commit's id, which doesn't change while the stash exists.
  let id: String
  /// The branch it was made on, or nil on a detached HEAD.
  let branch: String?
  /// The name you gave it, or for an unnamed one the subject of the commit
  /// it was made on top of.
  let message: String
  /// False for git's default "WIP on" message.
  let isNamed: Bool
  let date: Date

  var reference: String { "stash@{\(index)}" }

  /// What a row shows: the name, or "WIP: <commit subject>".
  var title: String { isNamed ? message : "WIP: \(message)" }

  /// For `git stash list --format=`: fields split by the unit separator.
  static let listFormat = "%gd%x1f%H%x1f%ct%x1f%gs"

  /// Reads `git stash list --format=<listFormat>`, one stash per line.
  static func parse(list: String) -> [Stash] {
    list.split(separator: "\n").compactMap { line in
      let fields = line.split(separator: "\u{1F}", maxSplits: 3, omittingEmptySubsequences: false)
      guard fields.count == 4, let index = Self.index(of: fields[0]) else { return nil }
      let (branch, message, isNamed) = Self.describe(subject: String(fields[3]))
      let seconds = TimeInterval(fields[2]) ?? 0
      return Stash(
        index: index, id: String(fields[1]), branch: branch, message: message, isNamed: isNamed,
        date: Date(timeIntervalSince1970: seconds))
    }
  }

  /// `stash@{3}` gives 3.
  private static func index(of selector: Substring) -> Int? {
    guard selector.hasPrefix("stash@{"), selector.hasSuffix("}") else { return nil }
    return Int(selector.dropFirst("stash@{".count).dropLast())
  }

  /// Splits git's subject: "On main: my name" is a named stash, "WIP on
  /// main: 1a2b3c4 Fix it" an unnamed one. Branch names can't contain ":",
  /// so the first ": " ends the branch. Anything else (a rebase's
  /// "autostash") is shown as it is.
  private static func describe(subject: String) -> (branch: String?, message: String, isNamed: Bool) {
    for (prefix, isNamed) in [("WIP on ", false), ("On ", true)] where subject.hasPrefix(prefix) {
      let rest = subject.dropFirst(prefix.count)
      guard let colon = rest.range(of: ": ") else { continue }
      let name = String(rest[..<colon.lowerBound])
      let branch = name == "(no branch)" ? nil : name
      var message = String(rest[colon.upperBound...])
      if !isNamed, let space = message.firstIndex(of: " "),
        message[..<space].allSatisfy(\.isHexDigit)
      {
        // Drop the short commit id; the subject says more.
        message = String(message[message.index(after: space)...])
      }
      return (branch, message, isNamed)
    }
    return (nil, subject, true)
  }
}

/// What a new stash takes, like Zed's three stash commands.
enum StashKind: String, Identifiable, CaseIterable, Sendable {
  /// Staged, unstaged, and untracked.
  case all
  /// Staged and unstaged changes to tracked files; untracked files stay.
  case tracked
  /// Only what's staged. Needs git 2.35 or later.
  case staged

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all: "Stash All Changes"
    case .tracked: "Stash Tracked Changes"
    case .staged: "Stash Staged Changes"
    }
  }

  /// What stays behind, in the name prompt.
  var explanation: String {
    switch self {
    case .all: "Sets aside everything, new files included."
    case .tracked: "Sets aside changes to tracked files. New files stay where they are."
    case .staged: "Sets aside what you've staged. Everything else stays where it is."
    }
  }

  /// `git` arguments to make the stash. An empty name leaves git's own
  /// "WIP on <branch>" message.
  func pushArguments(named name: String) -> [String] {
    var arguments = ["stash", "push"]
    switch self {
    case .all: arguments.append("--include-untracked")
    case .tracked: break
    case .staged: arguments.append("--staged")
    }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty { arguments += ["--message", trimmed] }
    return arguments
  }
}
