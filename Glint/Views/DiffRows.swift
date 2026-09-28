import Foundation

enum DiffLayout: String, CaseIterable, Sendable {
  case unified, split
}

/// Identifies one row of the rendered diff. Ordered top to bottom, so "the
/// next hunk after where the reader is" is a plain comparison.
struct DiffRowID: Hashable, Comparable, Sendable {
  let file: Int
  /// -1 for rows above the first hunk: the file header and any note.
  let hunk: Int
  /// -1 for headers.
  let line: Int

  /// Before every row.
  static let top = DiffRowID(file: -1, hunk: -1, line: -1)

  static func file(_ file: Int) -> DiffRowID { DiffRowID(file: file, hunk: -1, line: -1) }
  static func note(_ file: Int) -> DiffRowID { DiffRowID(file: file, hunk: -1, line: 0) }
  static func hunk(_ file: Int, _ hunk: Int) -> DiffRowID {
    DiffRowID(file: file, hunk: hunk, line: -1)
  }
  static func line(_ file: Int, _ hunk: Int, _ line: Int) -> DiffRowID {
    DiffRowID(file: file, hunk: hunk, line: line)
  }

  static func < (a: DiffRowID, b: DiffRowID) -> Bool {
    (a.file, a.hunk, a.line) < (b.file, b.hunk, b.line)
  }
}

/// A diff flattened into rows. One flat list, rather than nested sections,
/// keeps every row a direct child of the lazy stack, which is what lets the
/// stack realize only what is on screen and scroll to any row by id.
struct DiffRow: Identifiable, Sendable {
  enum Content: Sendable {
    case fileHeader(FileChange, collapsed: Bool)
    case note(String)
    case hunkHeader(Hunk)
    case line(DiffLine)
    case split(SplitRow)
  }

  let id: DiffRowID
  let content: Content
  /// The line's hunk both removes and adds lines. Style Zed marks such a
  /// hunk's changed lines with the modified colour, as Zed does.
  var inMixedHunk = false

  /// Why a file with no hunks is in the diff at all.
  static func emptyNote(_ status: FileChange.Status) -> String {
    switch status {
    case .added, .deleted: "Empty file."
    case .renamed: "Renamed, with no changes inside."
    case .copied: "Copied, with no changes inside."
    case .modified, .typeChanged: "Only the file's mode changed."
    }
  }

  static func build(_ diff: Diff, layout: DiffLayout, collapsed: Set<Int>) -> [DiffRow] {
    var rows: [DiffRow] = []
    let isSingleFile = diff.source.isSingleFile
    for file in diff.files {
      // One file's page header already names it and counts its lines.
      let isCollapsed = !isSingleFile && collapsed.contains(file.id)
      if !isSingleFile {
        rows.append(DiffRow(id: .file(file.id), content: .fileHeader(file, collapsed: isCollapsed)))
      }
      if isCollapsed { continue }

      if file.isBinary {
        rows.append(DiffRow(id: .note(file.id), content: .note("Binary file, not shown.")))
      } else if file.hunks.isEmpty {
        rows.append(DiffRow(id: .note(file.id), content: .note(Self.emptyNote(file.status))))
      }

      for hunk in file.hunks {
        rows.append(DiffRow(id: .hunk(file.id, hunk.id), content: .hunkHeader(hunk)))
        let mixed =
          hunk.lines.contains { $0.kind == .addition } && hunk.lines.contains { $0.kind == .deletion }
        switch layout {
        case .unified:
          for (index, line) in hunk.lines.enumerated() {
            rows.append(DiffRow(id: .line(file.id, hunk.id, index), content: .line(line), inMixedHunk: mixed))
          }
        case .split:
          for (index, row) in hunk.splitRows.enumerated() {
            rows.append(DiffRow(id: .line(file.id, hunk.id, index), content: .split(row), inMixedHunk: mixed))
          }
        }
      }
    }
    return rows
  }

  /// Digits in the largest line number, so the gutters fit without jitter.
  static func lineNumberDigits(_ diff: Diff) -> Int {
    var largest = 0
    for file in diff.files {
      for hunk in file.hunks {
        largest = max(largest, hunk.oldStart + hunk.oldCount, hunk.newStart + hunk.newCount)
      }
    }
    return max(String(largest).count, 3)
  }
}
