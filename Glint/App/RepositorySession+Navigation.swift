import Foundation

/// Moving around inside the diff on screen: layout, collapsing, file and hunk
/// jumps.
extension RepositorySession {
  func toggleLayout() {
    layout = layout == .unified ? .split : .unified
  }

  func toggleCollapsed(_ fileID: Int) {
    if collapsedFiles.remove(fileID) == nil { collapsedFiles.insert(fileID) }
  }

  func toggleCurrentFileCollapsed() {
    // A single file has no header to collapse it under.
    guard let diff, !diff.files.isEmpty, !diff.source.isSingleFile else { return }
    toggleCollapsed(max(cursor.file, 0))
    scroll(to: .file(max(cursor.file, 0)))
  }

  /// Called as the diff scrolls, with the rows now on screen.
  func visibleRowsChanged(_ rows: [DiffRowID]) {
    if let top = rows.min() { cursor = top }
  }

  func nextFile() {
    guard let files = diff?.files, cursor.file + 1 < files.count else { return }
    scroll(to: .file(cursor.file + 1))
  }

  func previousFile() {
    guard let files = diff?.files, !files.isEmpty else { return }
    // Inside a file, go back to its header first, like previous-hunk does.
    let target = cursor.hunk >= 0 ? cursor.file : max(cursor.file - 1, 0)
    scroll(to: .file(target))
  }

  func nextHunk() {
    guard let target = hunkAnchors().first(where: { $0 > cursor }) else { return }
    collapsedFiles.remove(target.file)
    scroll(to: target)
  }

  func previousHunk() {
    guard let target = hunkAnchors().last(where: { $0 < cursor }) else { return }
    collapsedFiles.remove(target.file)
    scroll(to: target)
  }

  private func hunkAnchors() -> [DiffRowID] {
    guard let files = diff?.files else { return [] }
    return files.flatMap { file in file.hunks.map { DiffRowID.hunk(file.id, $0.id) } }
  }

  /// Style Zed: brings the selected file's section of the all-files diff to
  /// the top.
  func scrollToSelectedFile() {
    guard let index = selectedDiffFileIndex else { return }
    scroll(to: .file(index))
  }

  /// Style Zed: where the file picked in the list is in Uncommitted Changes.
  var selectedDiffFileIndex: Int? {
    guard Theme.shared.isZed, tab == .changes, let path = selectedChange?.path else { return nil }
    return diff?.files.firstIndex { $0.newPath == path || $0.oldPath == path }
  }

  func scroll(to target: DiffRowID) {
    cursor = target
    diffScroller.scroll(to: target, rowsVersion: rowsVersion)
  }
}
