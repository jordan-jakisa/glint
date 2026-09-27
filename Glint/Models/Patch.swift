import Foundation

/// Builds the patches behind hunk and line staging. Staging part of a file
/// means applying part of its diff to the index; unstaging part of it means
/// applying the reverse. Both are the same move `git add -p` makes.
enum Patch {
  /// A patch that, applied to the index, stages the chosen changes from an
  /// unstaged hunk (index to working tree). With `unstage`, `hunk` comes from
  /// a staged diff (HEAD to index) and the patch takes the chosen changes back
  /// out of the index instead.
  ///
  /// `selected` holds indices into `hunk.lines`; nil takes every change in the
  /// hunk. Returns nil when the selection has no changed lines.
  static func make(
    path: String, isNewFile: Bool, hunk: Hunk, selected: Set<Int>?, unstage: Bool
  ) -> String? {
    var body: [String] = []
    var oldCount = 0
    var newCount = 0
    var changes = 0
    // Whether the line before a "\ No newline" marker made it into the patch.
    var previousKept = false

    for (index, line) in hunk.lines.enumerated() {
      let chosen = selected?.contains(index) ?? true
      // In the index's terms: what the line is now, and whether taking it
      // adds or removes it.
      let removesFromIndex: Bool
      switch line.kind {
      case .context:
        body.append(" " + line.text)
        oldCount += 1
        newCount += 1
        previousKept = true
        continue
      case .noNewline:
        if previousKept { body.append("\\ No newline at end of file") }
        continue
      case .addition:
        // Staging an addition adds it to the index. Unstaging one removes it.
        removesFromIndex = unstage
      case .deletion:
        removesFromIndex = !unstage
      }

      // Lines that exist in the index before the patch: staged additions when
      // unstaging, and deletions still in the index when staging.
      let inIndex = unstage ? line.kind == .addition : line.kind == .deletion
      if chosen {
        body.append((removesFromIndex ? "-" : "+") + line.text)
        if removesFromIndex { oldCount += 1 } else { newCount += 1 }
        changes += 1
        previousKept = true
      } else if inIndex {
        // Left alone: it stays in the index, so it's context here.
        body.append(" " + line.text)
        oldCount += 1
        newCount += 1
        previousKept = true
      } else {
        previousKept = false
      }
    }

    guard changes > 0 else { return nil }
    // The patch applies to the index, so its "old" side starts where the hunk
    // sits in the index: the old side of an unstaged hunk, the new side of a
    // staged one.
    let indexStart = unstage ? hunk.newStart : hunk.oldStart
    let oldStart = oldCount == 0 ? max(indexStart, 0) : max(indexStart, 1)
    let newStart = newCount == 0 ? max(oldStart - 1, 0) : (oldCount == 0 ? oldStart + 1 : oldStart)

    let creates = isNewFile && !unstage
    var lines = ["diff --git a/\(path) b/\(path)"]
    if creates { lines.append("new file mode 100644") }
    lines.append(creates ? "--- /dev/null" : "--- a/\(path)")
    lines.append("+++ b/\(path)")
    lines.append("@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@")
    lines.append(contentsOf: body)
    return lines.joined(separator: "\n") + "\n"
  }
}
