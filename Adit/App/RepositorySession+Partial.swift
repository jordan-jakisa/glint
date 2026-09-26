import Foundation

/// Staging and unstaging part of a file: one hunk, or chosen lines.
extension RepositorySession {
  /// Hunk and line actions exist only for a working-tree diff. Their verb
  /// depends on which side it shows.
  var partialAction: String? {
    guard tab == .changes, case .workingTree(let staged, _)? = diff?.source else { return nil }
    return staged ? "Unstage" : "Stage"
  }

  var isPartialStagingAvailable: Bool { partialAction != nil }

  func lineSelectionChanged(_ rows: [DiffRowID]) {
    selectedLineRows = rows
  }

  func stageHunk(_ row: DiffRowID) {
    guard let pick = pick(file: row.file, hunk: row.hunk, lines: nil) else { return }
    apply([pick])
  }

  func stageSelectedLines() {
    var groups: [DiffRowID: [Int]] = [:]
    for row in selectedLineRows where row.line >= 0 {
      groups[.hunk(row.file, row.hunk), default: []].append(row.line)
    }
    let picks = groups.compactMap { anchor, rowIndices in
      pick(file: anchor.file, hunk: anchor.hunk, lines: lineIndices(file: anchor.file, hunk: anchor.hunk, rows: rowIndices))
    }
    apply(picks)
  }

  /// `s`: the selected lines if there are any, else the hunk at the top of
  /// the view.
  func stageAtCursor() {
    if !selectedLineRows.isEmpty {
      stageSelectedLines()
      return
    }
    guard let files = diff?.files, !files.isEmpty else { return }
    let file = max(cursor.file, 0)
    let hunk = cursor.hunk >= 0 ? cursor.hunk : 0
    guard files.indices.contains(file), files[file].hunks.indices.contains(hunk) else { return }
    stageHunk(.hunk(file, hunk))
  }

  private struct Pick {
    let file: FileChange
    let hunk: Hunk
    let lines: Set<Int>?
  }

  private func pick(file fileID: Int, hunk hunkID: Int, lines: Set<Int>?) -> Pick? {
    guard let files = diff?.files, files.indices.contains(fileID) else { return nil }
    let file = files[fileID]
    guard file.hunks.indices.contains(hunkID) else { return nil }
    return Pick(file: file, hunk: file.hunks[hunkID], lines: lines)
  }

  /// Table rows to indices into `hunk.lines`. In split layout a row can hold a
  /// deletion and an addition; line numbers identify each within the hunk.
  private func lineIndices(file: Int, hunk hunkID: Int, rows: [Int]) -> Set<Int> {
    guard layout == .split, let hunk = pick(file: file, hunk: hunkID, lines: nil)?.hunk else {
      return Set(rows)
    }
    var result = Set<Int>()
    for row in rows where hunk.splitRows.indices.contains(row) {
      let pair = hunk.splitRows[row]
      if let left = pair.left, left.kind == .deletion,
        let index = hunk.lines.firstIndex(where: { $0.kind == .deletion && $0.oldNumber == left.oldNumber })
      {
        result.insert(index)
      }
      if let right = pair.right, right.kind == .addition,
        let index = hunk.lines.firstIndex(where: { $0.kind == .addition && $0.newNumber == right.newNumber })
      {
        result.insert(index)
      }
    }
    return result
  }

  private func apply(_ picks: [Pick]) {
    guard let repository, case .workingTree(let staged, _)? = diff?.source, !picks.isEmpty else { return }
    // Taking every change of an added or deleted file is the same as staging
    // the whole file, and only the whole-file path keeps the file's mode and
    // records a deletion as a deletion rather than as an empty file.
    var partial: [Pick] = []
    var wholeFiles: [String] = []
    for filePicks in Dictionary(grouping: picks, by: { $0.file.id }).values {
      let file = filePicks[0].file
      if file.status == .added || file.status == .deleted, Self.coversEveryChange(file, filePicks) {
        wholeFiles.append(file.path)
      } else {
        partial.append(contentsOf: filePicks)
      }
    }
    for path in wholeFiles { setStaged(path, !staged) }
    guard !partial.isEmpty else {
      selectedLineRows = []
      return
    }
    applyPatches(partial, staged: staged, repository: repository)
  }

  private static func coversEveryChange(_ file: FileChange, _ picks: [Pick]) -> Bool {
    for hunk in file.hunks {
      let changed = Set(hunk.lines.indices.filter { hunk.lines[$0].kind == .addition || hunk.lines[$0].kind == .deletion })
      guard let pick = picks.first(where: { $0.hunk.id == hunk.id }) else { return false }
      if let lines = pick.lines, !changed.isSubset(of: lines) { return false }
    }
    return true
  }

  private func applyPatches(_ picks: [Pick], staged: Bool, repository: GitRepository) {
    // Within a file, apply bottom hunks first so line numbers above them in
    // the index stay valid for the next patch.
    let ordered = picks.sorted { ($0.file.id, $0.hunk.id) > ($1.file.id, $1.hunk.id) }
    let patches = ordered.compactMap { pick in
      Patch.make(
        path: pick.file.path, isNewFile: !staged && pick.file.status == .added,
        hunk: pick.hunk, selected: pick.lines, unstage: staged)
    }
    guard !patches.isEmpty else { return }
    Timing.writes.notice("\(staged ? "unstage" : "stage", privacy: .public) \(patches.count) partial patch(es)")
    selectedLineRows = []
    Task {
      let start = ContinuousClock.now
      do {
        for patch in patches { try await repository.applyToIndex(patch) }
        Timing.report("partial staging", since: start, budget: 100)
      } catch {
        alertMessage = "\(error)"
      }
      refreshWorkingTree()
    }
  }
}
