import Foundation

/// Everything that changed in one commit, relative to its first parent.
struct CommitDiff: Sendable {
  let commitID: String
  let files: [FileChange]

  var additions: Int { files.reduce(0) { $0 + $1.additions } }
  var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
}

struct FileChange: Identifiable, Sendable {
  enum Status: Sendable {
    case added, deleted, modified, renamed, copied, typeChanged
  }

  /// Position in the diff. Stable for the lifetime of one `CommitDiff`.
  let id: Int
  let status: Status
  let oldPath: String?
  let newPath: String?
  let isBinary: Bool
  let hunks: [Hunk]
  let additions: Int
  let deletions: Int

  var path: String { newPath ?? oldPath ?? "" }
}

struct Hunk: Identifiable, Sendable {
  /// Position within its file.
  let id: Int
  let header: String
  let oldStart: Int
  let oldCount: Int
  let newStart: Int
  let newCount: Int
  let lines: [DiffLine]
  /// The same lines paired up for side-by-side display.
  let splitRows: [SplitRow]

  init(
    id: Int, header: String, oldStart: Int, oldCount: Int, newStart: Int,
    newCount: Int, lines: [DiffLine]
  ) {
    self.id = id
    self.header = header
    self.oldStart = oldStart
    self.oldCount = oldCount
    self.newStart = newStart
    self.newCount = newCount
    self.lines = lines
    self.splitRows = SplitRow.pair(lines)
  }
}

struct DiffLine: Sendable, Equatable {
  enum Kind: Sendable {
    case context, addition, deletion
    /// "\ No newline at end of file". Carries no line numbers.
    case noNewline
  }

  let kind: Kind
  let oldNumber: Int?
  let newNumber: Int?
  let text: String
}

/// One row of the split view. Either side can be empty.
struct SplitRow: Sendable, Equatable {
  let left: DiffLine?
  let right: DiffLine?

  /// Pairs a hunk's lines the way side-by-side diff tools do: context lines sit
  /// on both sides, and a run of deletions lines up against the run of
  /// additions that follows it.
  static func pair(_ lines: [DiffLine]) -> [SplitRow] {
    var rows: [SplitRow] = []
    rows.reserveCapacity(lines.count)
    var deletions: [DiffLine] = []
    var additions: [DiffLine] = []

    func flush() {
      for i in 0..<max(deletions.count, additions.count) {
        rows.append(
          SplitRow(
            left: i < deletions.count ? deletions[i] : nil,
            right: i < additions.count ? additions[i] : nil))
      }
      deletions.removeAll(keepingCapacity: true)
      additions.removeAll(keepingCapacity: true)
    }

    for (index, line) in lines.enumerated() {
      switch line.kind {
      case .deletion:
        if !additions.isEmpty { flush() }
        deletions.append(line)
      case .addition:
        additions.append(line)
      case .context:
        flush()
        rows.append(SplitRow(left: line, right: line))
      case .noNewline:
        // The marker belongs to whichever side the line before it was on.
        let previous = index > 0 ? lines[index - 1].kind : .context
        switch previous {
        case .deletion: deletions.append(line)
        case .addition: additions.append(line)
        default:
          flush()
          rows.append(SplitRow(left: line, right: line))
        }
      }
    }
    flush()
    return rows
  }
}
