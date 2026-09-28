import Foundation

/// One merge conflict in a file: the lines between `<<<<<<<` and `>>>>>>>`.
struct ConflictRegion: Identifiable, Hashable, Sendable {
  /// Its place among the file's conflicts, from 0.
  let index: Int
  /// Lines from the `<<<<<<<` marker through the `>>>>>>>` one, 0-based and
  /// half-open, in the file's lines.
  let lines: Range<Int>
  /// Your side, the one checked out when the merge started.
  let current: [String]
  /// The side being merged in.
  let incoming: [String]
  /// The common ancestor, when the markers are diff3 style. Resolving
  /// drops it.
  let base: [String]?
  /// What the marker lines name, usually a branch or a commit.
  let currentLabel: String
  let incomingLabel: String

  var id: Int { index }
}

/// What to keep of a conflict.
enum ConflictChoice: Sendable {
  case current, incoming
  /// Current first, then incoming.
  case both
}

/// Finding and resolving conflict markers in a file's text. Pure, so the
/// parsing and rewriting are tested without a repository.
enum Conflict {
  /// Git's default marker length (`conflict-marker-size`).
  private static let markerLength = 7

  /// The file's lines without line endings, and whether it ends in a newline.
  static func lines(of content: String) -> (lines: [String], endsWithNewline: Bool) {
    var lines = content.components(separatedBy: "\n").map(withoutCR)
    let endsWithNewline = content.hasSuffix("\n")
    if endsWithNewline { lines.removeLast() }
    if content.isEmpty { lines = [] }
    return (lines, endsWithNewline)
  }

  /// Every complete conflict in `content`, in order. A region missing its
  /// closing marker isn't one.
  static func parse(_ content: String) -> [ConflictRegion] {
    parse(lines: lines(of: content).lines)
  }

  static func parse(lines: [String]) -> [ConflictRegion] {
    enum Section { case current, base, incoming }
    var regions: [ConflictRegion] = []
    var start: Int?
    var section = Section.current
    var current: [String] = [], base: [String]?, incoming: [String] = []
    var currentLabel = ""

    for (number, line) in lines.enumerated() {
      if let label = marker("<", in: line) {
        // A new opening marker restarts, so a stray one doesn't swallow the file.
        start = number
        section = .current
        current = []
        base = nil
        incoming = []
        currentLabel = label
        continue
      }
      guard let open = start else { continue }
      switch section {
      case .current, .base:
        if marker("|", in: line) != nil, section == .current {
          section = .base
          base = []
        } else if isSeparator(line) {
          section = .incoming
        } else if section == .current {
          current.append(line)
        } else {
          base?.append(line)
        }
      case .incoming:
        if let label = marker(">", in: line) {
          regions.append(
            ConflictRegion(
              index: regions.count, lines: open..<(number + 1), current: current, incoming: incoming,
              base: base, currentLabel: currentLabel, incomingLabel: label))
          start = nil
        } else {
          incoming.append(line)
        }
      }
    }
    return regions
  }

  /// `content` with `region` replaced by the lines `choice` keeps. Line
  /// endings and the final newline stay as they were. Returns `content`
  /// unchanged if the region isn't where it was found.
  static func resolving(region: ConflictRegion, choice: ConflictChoice, in content: String) -> String {
    let lineEnding = content.contains("\r\n") ? "\r\n" : "\n"
    let split = Conflict.lines(of: content)
    var lines = split.lines
    guard region.lines.lowerBound >= 0, region.lines.upperBound <= lines.count,
      marker("<", in: lines[region.lines.lowerBound]) != nil,
      marker(">", in: lines[region.lines.upperBound - 1]) != nil
    else { return content }
    let kept: [String] =
      switch choice {
      case .current: region.current
      case .incoming: region.incoming
      case .both: region.current + region.incoming
      }
    lines.replaceSubrange(region.lines, with: kept)
    // Keeping nothing from a file that was only a conflict leaves it empty.
    if lines.isEmpty { return "" }
    return lines.joined(separator: lineEnding) + (split.endsWithNewline ? lineEnding : "")
  }

  /// The label after a marker made of `character`, or nil if `line` isn't
  /// one. "<<<<<<< HEAD" gives "HEAD"; a bare marker gives "".
  private static func marker(_ character: Character, in line: String) -> String? {
    let prefix = String(repeating: character, count: markerLength)
    guard line.hasPrefix(prefix) else { return nil }
    let rest = line.dropFirst(markerLength)
    guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
    return rest.trimmingCharacters(in: .whitespaces)
  }

  private static func isSeparator(_ line: String) -> Bool {
    line.trimmingCharacters(in: .whitespaces) == String(repeating: "=", count: markerLength)
  }

  private static func withoutCR(_ line: String) -> String {
    line.hasSuffix("\r") ? String(line.dropLast()) : line
  }
}

/// A conflicted file as last read from disk, for the conflict view.
struct ConflictDocument: Equatable, Sendable {
  let path: String
  /// The file's text, or nil when it couldn't be read as text (deleted on
  /// one side, or binary).
  let content: String?
  let lines: [String]
  let regions: [ConflictRegion]

  init(path: String, content: String?) {
    self.path = path
    self.content = content
    lines = content.map { Conflict.lines(of: $0).lines } ?? []
    regions = Conflict.parse(lines: lines)
  }
}
