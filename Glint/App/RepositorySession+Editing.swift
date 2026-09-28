import Foundation

/// A hunk of your working copy, open for editing in the diff.
struct HunkEdit: Identifiable {
  let id = UUID()
  /// Path from the repository root, and the file's name for the title.
  let path: String
  let fileName: String
  /// First line of the hunk's new side, 1-based.
  let startLine: Int
  /// The lines as the diff showed them, to check the file hasn't moved on.
  let original: [String]
  var text: String

  var endLine: Int { startLine + max(original.count, 1) - 1 }
}

/// Editing in the diff: a hunk's current lines open in an editor and save
/// straight back to the file, which the watcher then shows as a new diff.
extension RepositorySession {
  /// Whether the diff on screen is your working copy, the only one edits
  /// can go to.
  var canEditDiff: Bool {
    if case .workingTree(false, _) = diff?.source { return true }
    return false
  }

  func beginEdit(_ row: DiffRowID) {
    guard canEditDiff, let files = diff?.files, files.indices.contains(row.file) else { return }
    let file = files[row.file]
    guard let path = file.newPath, !file.isBinary, file.hunks.indices.contains(row.hunk) else { return }
    let hunk = file.hunks[row.hunk]
    // The file as it is now: context and added lines, not the removed ones.
    let current = hunk.lines.filter { $0.kind == .context || $0.kind == .addition }.map { Self.withoutCR($0.text) }
    guard !current.isEmpty else { return }
    editingHunk = HunkEdit(
      path: path, fileName: (path as NSString).lastPathComponent, startLine: hunk.newStart,
      original: current, text: current.joined(separator: "\n"))
  }

  /// Writes the edited lines over the ones the diff showed. Refuses if the
  /// file changed underneath, rather than overwrite work it hasn't seen.
  func saveEdit(_ edit: HunkEdit) {
    guard let repository else { return }
    let url = repository.url.appendingPathComponent(edit.path)
    do {
      let content = try String(contentsOf: url, encoding: .utf8)
      guard let output = Self.applying(edit, to: content) else {
        alert = UserAlert(
          "Couldn't save your edit",
          message: "\(edit.fileName) changed since the diff was shown. Look at the new diff, then edit again.")
        return
      }
      try output.write(to: url, atomically: true, encoding: .utf8)
      Timing.writes.notice("edit in diff")
      editingHunk = nil
      refresh()
    } catch {
      alert = UserAlert("Couldn't save your edit", error: error)
    }
  }

  /// The file with the edit applied, keeping its line endings and final
  /// newline; nil if the lines the diff showed aren't there any more.
  nonisolated static func applying(_ edit: HunkEdit, to content: String) -> String? {
    let lineEnding = content.contains("\r\n") ? "\r\n" : "\n"
    var lines = content.components(separatedBy: "\n").map(withoutCR)
    let endsWithNewline = content.hasSuffix("\n")
    if endsWithNewline { lines.removeLast() }
    let range = (edit.startLine - 1)..<(edit.startLine - 1 + edit.original.count)
    guard range.lowerBound >= 0, range.upperBound <= lines.count, Array(lines[range]) == edit.original else {
      return nil
    }
    var replacement = edit.text.components(separatedBy: "\n").map(withoutCR)
    // A trailing newline typed at the end is the line break, not a new line.
    if replacement.count > 1, replacement.last == "" { replacement.removeLast() }
    lines.replaceSubrange(range, with: replacement)
    return lines.joined(separator: lineEnding) + (endsWithNewline ? lineEnding : "")
  }

  nonisolated private static func withoutCR(_ line: String) -> String {
    line.hasSuffix("\r") ? String(line.dropLast()) : line
  }
}
