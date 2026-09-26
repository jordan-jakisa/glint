import Testing

@testable import Adit

@Suite struct SplitRowTests {
  private func line(_ kind: DiffLine.Kind, _ text: String, old: Int? = nil, new: Int? = nil)
    -> DiffLine
  {
    DiffLine(kind: kind, oldNumber: old, newNumber: new, text: text)
  }

  @Test func contextSitsOnBothSides() {
    let context = line(.context, "same", old: 1, new: 1)
    #expect(SplitRow.pair([context]) == [SplitRow(left: context, right: context)])
  }

  @Test func deletionsPairWithFollowingAdditions() {
    let d1 = line(.deletion, "a", old: 1)
    let d2 = line(.deletion, "b", old: 2)
    let a1 = line(.addition, "A", new: 1)
    let rows = SplitRow.pair([d1, d2, a1])
    #expect(rows == [SplitRow(left: d1, right: a1), SplitRow(left: d2, right: nil)])
  }

  @Test func additionThenDeletionDoNotPair() {
    let a = line(.addition, "new", new: 1)
    let d = line(.deletion, "old", old: 1)
    let rows = SplitRow.pair([a, d])
    #expect(rows == [SplitRow(left: nil, right: a), SplitRow(left: d, right: nil)])
  }

  @Test func contextBreaksRuns() {
    let d = line(.deletion, "x", old: 1)
    let c = line(.context, "c", old: 2, new: 1)
    let a = line(.addition, "y", new: 2)
    let rows = SplitRow.pair([d, c, a])
    #expect(
      rows == [
        SplitRow(left: d, right: nil), SplitRow(left: c, right: c), SplitRow(left: nil, right: a),
      ])
  }

  @Test func noNewlineMarkerFollowsItsSide() {
    let d = line(.deletion, "x", old: 1)
    let a = line(.addition, "y", new: 1)
    let marker = line(.noNewline, "No newline at end of file")
    let rows = SplitRow.pair([d, a, marker])
    #expect(rows == [SplitRow(left: d, right: a), SplitRow(left: nil, right: marker)])
  }
}

@Suite struct DiffRowTests {
  private func sampleDiff() -> Diff {
    let lines = [
      DiffLine(kind: .context, oldNumber: 9, newNumber: 9, text: "a"),
      DiffLine(kind: .deletion, oldNumber: 10, newNumber: nil, text: "b"),
      DiffLine(kind: .addition, oldNumber: nil, newNumber: 10, text: "c"),
    ]
    let hunk = Hunk(
      id: 0, header: "@@ -9,2 +9,2 @@", oldStart: 9, oldCount: 2, newStart: 9, newCount: 2,
      lines: lines)
    return Diff(
      source: .commit("abc"),
      files: [
        FileChange(
          id: 0, status: .modified, oldPath: "f", newPath: "f", isBinary: false, hunks: [hunk],
          additions: 1, deletions: 1),
        FileChange(
          id: 1, status: .added, oldPath: nil, newPath: "img", isBinary: true, hunks: [],
          additions: 0, deletions: 0),
      ])
  }

  @Test func unifiedHasOneRowPerLine() {
    let rows = DiffRow.build(sampleDiff(), layout: .unified, collapsed: [])
    // file header, hunk header, 3 lines, file header, binary note
    #expect(rows.count == 7)
    #expect(rows.map(\.id) == rows.map(\.id).sorted())
    #expect(Set(rows.map(\.id)).count == rows.count)
  }

  @Test func splitPairsLines() {
    let rows = DiffRow.build(sampleDiff(), layout: .split, collapsed: [])
    // file header, hunk header, 2 paired rows, file header, binary note
    #expect(rows.count == 6)
  }

  @Test func collapsedFileKeepsOnlyItsHeader() {
    let rows = DiffRow.build(sampleDiff(), layout: .unified, collapsed: [0])
    #expect(rows.map(\.id) == [.file(0), .file(1), .note(1)])
  }

  @Test func gutterFitsTheLargestLineNumber() {
    #expect(DiffRow.lineNumberDigits(sampleDiff()) == 3)
  }

  @Test func rowOrderMatchesReadingOrder() {
    #expect(DiffRowID.top < .file(0))
    #expect(DiffRowID.file(0) < .note(0))
    #expect(DiffRowID.note(0) < .hunk(0, 0))
    #expect(DiffRowID.hunk(0, 0) < .line(0, 0, 0))
    #expect(DiffRowID.line(0, 0, 99) < .hunk(0, 1))
    #expect(DiffRowID.hunk(0, 5) < .file(1))
  }
}

@Suite struct RepositoryWatcherTests {
  @Test func classifiesPaths() {
    let root = "/repo"
    #expect(RepositoryWatcher.classify("/repo/src/a.swift", root: root) == .workingTree)
    #expect(RepositoryWatcher.classify("/repo/.gitignore", root: root) == .workingTree)
    #expect(RepositoryWatcher.classify("/repo/.git/index", root: root) == .workingTree)
    #expect(RepositoryWatcher.classify("/repo/.git/HEAD", root: root) == .head)
    #expect(RepositoryWatcher.classify("/repo/.git/refs/heads/main", root: root) == .head)
    #expect(RepositoryWatcher.classify("/repo/.git/packed-refs", root: root) == .head)
    #expect(RepositoryWatcher.classify("/repo/.git/objects/ab/cdef", root: root) == .ignored)
    #expect(RepositoryWatcher.classify("/repo/.git/index.lock", root: root) == .ignored)
    #expect(RepositoryWatcher.classify("/repo/.git/logs/HEAD", root: root) == .ignored)
  }
}
