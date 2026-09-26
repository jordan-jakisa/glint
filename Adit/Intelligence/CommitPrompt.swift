import Foundation

/// Everything about turning a diff into a request for a commit message, and
/// the model's reply back into one. Pure functions, so they're tested without
/// a network.
enum CommitPrompt {
  /// Diffs past this size get squeezed before they're sent. Big enough for a
  /// normal commit, small enough for free models' context and rate limits.
  static let maxDiffBytes = 20_000

  static let instructions = """
    Write a git commit message for the changes below.

    - Subject line: imperative mood, capitalized, no period at the end, about 50 characters or fewer. Say what changed in terms a reader cares about, not which files were touched.
    - A good message says why the change was made, not just what changed. Add a body only when the diff, or the user's own words, show the reason. If the reason isn't visible, stop after the subject rather than guess.
    - Put a blank line after the subject and wrap the body at 72 characters. Keep it short, and don't repeat the subject in the body.
    - Reply with the commit message and nothing else: no preamble, no quotes, no code fences, and don't include the diff.
    """

  /// Files in a repository's root that hold its conventions for agents, in the
  /// order they're looked for. The first one found is sent along.
  static let rulesFiles = [
    ".rules", "AGENTS.md", "AGENT.md", "CLAUDE.md", "GEMINI.md", ".cursorrules",
    ".github/copilot-instructions.md",
  ]

  static func build(
    diff: String, subject: String, rules: String?, userInstructions: String?,
    recentSubjects: [String] = [], userWhy: String? = nil
  ) -> String {
    var prompt = instructions
    if let rules, !rules.isEmpty {
      prompt += "\n\nThis repository has its own conventions. Follow them where they cover commit messages:\n<repository_rules>\n\(rules)\n</repository_rules>"
    }
    if let userInstructions, !userInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      prompt += "\n\nThe user's own instructions for commit messages:\n<instructions>\n\(userInstructions)\n</instructions>"
    }
    let recent = recentSubjects.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.prefix(10)
    if !recent.isEmpty {
      prompt += "\n\nRecent commit subjects in this repository. Match their style (tense, prefixes, capitalization), not their content:\n<recent_commits>\n\(recent.joined(separator: "\n"))\n</recent_commits>"
    }
    let subject = subject.trimmingCharacters(in: .whitespaces)
    if !subject.isEmpty {
      prompt += "\n\nThe user already wrote this subject line. Start the message with it, unchanged:\n\(subject)"
    }
    if let userWhy, !userWhy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      prompt += "\n\nThe user explained why they made this change. Use it for the body and keep its meaning:\n<why>\n\(userWhy.trimmingCharacters(in: .whitespacesAndNewlines))\n</why>"
    }
    return prompt + "\n\nThe changes:\n\(diff)"
  }

  /// Messages generators get wrong in known ways (Tian et al., ICSE 2022):
  /// a single word, only a vague scope ("minor changes"), or a file name
  /// restated as the whole subject. Better to show nothing than one of these.
  static func isWeak(_ message: String) -> Bool {
    let subject = message.components(separatedBy: "\n").first?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let words = subject.split(whereSeparator: \.isWhitespace)
    if words.count <= 1 { return true }
    let normalized = subject.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
    let vague = [
      "minor changes", "minor fixes", "small changes", "small fixes", "some changes", "various changes",
      "update files", "update code", "fix bugs", "fix bug", "changes", "wip", "misc", "cleanup", "code cleanup",
      "update", "updates", "fix stuff", "more changes", "improvements",
    ]
    if vague.contains(normalized) { return true }
    // "Update foo.swift", "Add bar.txt": a verb and nothing but a file name.
    if words.count == 2, words[1].contains("."), !words[1].hasSuffix(".") { return true }
    return false
  }

  /// How much of a generated message was changed before committing, from 0
  /// (kept as written) to 1 (rewritten): edit distance over the longer
  /// length. Real users' edits track message quality better than BLEU-style
  /// scores (Tsvetkov et al., ICSE 2025).
  static func editRatio(from generated: String, to committed: String) -> Double {
    let a = Array(generated.trimmingCharacters(in: .whitespacesAndNewlines))
    let b = Array(committed.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !a.isEmpty || !b.isEmpty else { return 0 }
    var previous = Array(0...b.count)
    for i in 1...max(a.count, 1) where !a.isEmpty {
      var current = [i] + Array(repeating: 0, count: b.count)
      for j in stride(from: 1, through: b.count, by: 1) {
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
      }
      previous = current
    }
    let distance = a.isEmpty ? b.count : previous[b.count]
    return Double(distance) / Double(max(a.count, b.count))
  }

  /// A diff as `git diff` would print it.
  static func patchText(_ diff: Diff) -> String {
    var out = ""
    for file in diff.files {
      let old = file.oldPath.map { "a/\($0)" } ?? "/dev/null"
      let new = file.newPath.map { "b/\($0)" } ?? "/dev/null"
      out += "diff --git a/\(file.oldPath ?? file.path) b/\(file.newPath ?? file.path)\n"
      if file.isBinary {
        out += "Binary file \(file.path) changed\n"
        continue
      }
      out += "--- \(old)\n+++ \(new)\n"
      for hunk in file.hunks {
        out += hunk.header + "\n"
        for line in hunk.lines {
          switch line.kind {
          case .context: out += " \(line.text)\n"
          case .addition: out += "+\(line.text)\n"
          case .deletion: out += "-\(line.text)\n"
          case .noNewline: out += "\\ No newline at end of file\n"
          }
        }
      }
    }
    return out
  }

  /// Squeezes a diff under `maxBytes`: first by clipping very long lines
  /// (minified files, lockfiles), then by leaving out the last hunks of
  /// whichever file has the most, a hunk at a time, so every file keeps at
  /// least its first hunk. The model sees that something was left out.
  static func compress(_ diff: String, maxBytes: Int = maxDiffBytes) -> String {
    guard diff.utf8.count > maxBytes else { return diff }
    let clipped = diff.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
      line.utf8.count > 256 ? String(line.prefix(256)) + "…[line clipped]" : String(line)
    }.joined(separator: "\n")
    guard clipped.utf8.count > maxBytes else { return clipped }

    var files = FilePatch.split(clipped)
    var size = files.reduce(0) { $0 + $1.size }
    while size > maxBytes {
      guard let index = files.indices.filter({ files[$0].kept > 1 }).max(by: { files[$0].kept < files[$1].kept })
      else { break }
      let before = files[index].size
      files[index].kept -= 1
      size -= before - files[index].size
    }
    return files.map(\.text).joined()
  }

  /// Tidies a model's reply: drops a reasoning block some free models put in
  /// the answer, and code fences around the message. While the reply is still
  /// streaming, an unfinished reasoning block is hidden.
  static func clean(_ reply: String) -> String {
    var text = reply
    while let open = text.range(of: "<think>") {
      if let close = text.range(of: "</think>", range: open.upperBound..<text.endIndex) {
        text.removeSubrange(open.lowerBound..<close.upperBound)
      } else {
        text.removeSubrange(open.lowerBound..<text.endIndex)
      }
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.hasPrefix("```") {
      var lines = text.components(separatedBy: "\n")
      lines.removeFirst()
      if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true { lines.removeLast() }
      text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return text
  }
}

/// One file's part of a diff, split into its header and hunks, with how many
/// hunks are being kept.
private struct FilePatch {
  var header: String
  var hunks: [String]
  var kept: Int

  var size: Int { text.utf8.count }

  var text: String {
    var out = header + hunks.prefix(kept).joined()
    if kept < hunks.count {
      out += "[\(hunks.count - kept) more hunks in this file left out]\n"
    }
    return out
  }

  static func split(_ diff: String) -> [FilePatch] {
    var files: [FilePatch] = []
    for line in diff.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(line) + "\n"
      if line.hasPrefix("diff --git ") || files.isEmpty {
        files.append(FilePatch(header: line, hunks: [], kept: 0))
      } else if line.hasPrefix("@@") {
        files[files.count - 1].hunks.append(line)
        files[files.count - 1].kept += 1
      } else if files[files.count - 1].hunks.isEmpty {
        files[files.count - 1].header += line
      } else {
        files[files.count - 1].hunks[files[files.count - 1].hunks.count - 1] += line
      }
    }
    return files
  }
}
