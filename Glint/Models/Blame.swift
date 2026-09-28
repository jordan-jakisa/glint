import Foundation

/// Who last changed a line, and when: one commit as `git blame` reports it.
struct BlameCommit: Sendable, Equatable {
  /// Full hex id; all zeros for a line that isn't committed yet.
  let id: String
  let author: String
  let authorMail: String
  let date: Date
  let summary: String

  static let uncommittedID = String(repeating: "0", count: 40)

  /// A line you've written but not committed.
  static let uncommitted = BlameCommit(
    id: uncommittedID, author: "", authorMail: "", date: .distantFuture, summary: "")

  var isCommitted: Bool { id != Self.uncommittedID }
  var shortID: String { String(id.prefix(7)) }

  /// The author's first name, cut to `limit` characters, for the gutter.
  func shortAuthor(limit: Int = 8) -> String {
    let first = author.split(separator: " ").first.map(String.init) ?? author
    guard first.count > limit else { return first }
    return String(first.prefix(limit - 1)) + "\u{2026}"
  }

  /// "Jordan, 3 days ago · Fix the thing", shown after a selected line.
  func inlineText(now: Date = Date()) -> String {
    guard isCommitted else { return "Not committed yet" }
    let when = BlameDate.text(for: date, now: now)
    return summary.isEmpty ? "\(author), \(when)" : "\(author), \(when) \u{00B7} \(summary)"
  }

  /// The whole story, for the gutter's tooltip.
  var tooltip: String {
    guard isCommitted else { return "Not committed yet" }
    let when = date.formatted(date: .abbreviated, time: .shortened)
    let who = authorMail.isEmpty ? author : "\(author) \(authorMail)"
    return "\(shortID) \(summary)\n\(who)\n\(when)"
  }
}

/// One line of a blamed file: its text, to check it still matches the diff,
/// and the commit that last changed it.
struct BlameLine: Sendable, Equatable {
  let commit: BlameCommit
  let text: String

  /// Whether this is still the line the diff shows. Carriage returns are
  /// ignored, since the diff and blame may disagree on keeping them.
  func matches(_ other: String) -> Bool {
    Self.withoutCR(text) == Self.withoutCR(other)
  }

  private static func withoutCR(_ line: String) -> Substring {
    line.hasSuffix("\r") ? line.dropLast() : Substring(line)
  }
}

/// A file's blame, by final line number.
struct Blame: Sendable {
  /// Index 0 is line 1. Nil for a line the output skipped.
  let lines: [BlameLine?]

  func line(_ number: Int) -> BlameLine? {
    guard number >= 1, number <= lines.count else { return nil }
    return lines[number - 1]
  }

  /// Reads `git blame --porcelain`. Each group of lines starts with
  /// `<sha> <orig> <final> [<count>]`; the first time a commit appears its
  /// details follow (`author`, `author-time`, `summary`...), and every line
  /// ends with its text after a tab.
  static func parse(porcelain: String) -> Blame {
    struct Details {
      var author = ""
      var mail = ""
      var time: TimeInterval = 0
      var summary = ""
    }
    var details: [String: Details] = [:]
    var current: String?
    var finalLine = 0
    var found: [(line: Int, sha: String, text: String)] = []

    for raw in porcelain.split(separator: "\n", omittingEmptySubsequences: false) {
      if raw.hasPrefix("\t") {
        if let current, finalLine > 0 { found.append((finalLine, current, String(raw.dropFirst()))) }
        continue
      }
      let parts = raw.split(separator: " ", maxSplits: 1)
      guard let key = parts.first else { continue }
      let value = parts.count > 1 ? String(parts[1]) : ""
      if isHeader(key, value) {
        let sha = String(key)
        current = sha
        let numbers = value.split(separator: " ")
        finalLine = numbers.count > 1 ? Int(numbers[1]) ?? 0 : 0
        if details[sha] == nil { details[sha] = Details() }
        continue
      }
      guard let sha = current else { continue }
      switch key {
      case "author": details[sha]?.author = value
      case "author-mail": details[sha]?.mail = value
      case "author-time": details[sha]?.time = TimeInterval(value) ?? 0
      case "summary": details[sha]?.summary = value
      default: break
      }
    }

    var commits: [String: BlameCommit] = [:]
    for (sha, detail) in details {
      commits[sha] =
        sha == BlameCommit.uncommittedID
        ? .uncommitted
        : BlameCommit(
          id: sha, author: detail.author, authorMail: detail.mail,
          date: Date(timeIntervalSince1970: detail.time), summary: detail.summary)
    }
    let count = found.map(\.line).max() ?? 0
    var lines = [BlameLine?](repeating: nil, count: count)
    for entry in found {
      guard let commit = commits[entry.sha] else { continue }
      lines[entry.line - 1] = BlameLine(commit: commit, text: entry.text)
    }
    return Blame(lines: lines)
  }

  /// `<40 hex> <orig> <final>`, as opposed to a `key value` detail line.
  private static func isHeader(_ key: Substring, _ value: String) -> Bool {
    guard key.utf8.count == 40, key.utf8.allSatisfy({ isHex($0) }) else { return false }
    let numbers = value.split(separator: " ")
    return numbers.count >= 2 && numbers.allSatisfy { Int($0) != nil }
  }

  private static func isHex(_ byte: UInt8) -> Bool {
    (byte >= 48 && byte <= 57) || (byte >= 97 && byte <= 102) || (byte >= 65 && byte <= 70)
  }
}

/// "3 days ago", short enough for the blame gutter.
enum BlameDate {
  static func text(for date: Date, now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    let minute = 60.0
    let hour = 60 * minute
    let day = 24 * hour
    func count(_ value: Double, _ unit: String, _ units: String) -> String {
      let n = Int(value)
      return "\(n) \(n == 1 ? unit : units) ago"
    }
    switch seconds {
    case ..<minute: return "just now"
    case ..<hour: return count(seconds / minute, "min", "min")
    case ..<day: return count(seconds / hour, "hr", "hr")
    case ..<(14 * day): return count(seconds / day, "day", "days")
    case ..<(60 * day): return count(seconds / (7 * day), "wk", "wk")
    case ..<(365 * day): return count(seconds / (30 * day), "mo", "mo")
    default: return count(seconds / (365 * day), "yr", "yr")
    }
  }

  /// The longest `text` can be, so the gutter never changes width.
  static let maxLength = "13 days ago".count
}
