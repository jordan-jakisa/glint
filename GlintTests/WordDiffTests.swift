import Foundation
import Testing

@testable import Glint

/// Word diff: which characters of a changed line changed, and restoring a
/// hunk from the working copy.
@Suite struct WordDiffTests {
  private func text(_ string: String, _ ranges: [Range<Int>]) -> [String] {
    let units = Array(string.utf16)
    return ranges.map { String(decoding: units[$0], as: UTF16.self) }
  }

  @Test func marksOnlyTheChangedWord() throws {
    let old = "let count = items.count + 1"
    let new = "let total = items.count + 1"
    let ranges = try #require(WordDiff.ranges(old: old, new: new))
    #expect(text(old, ranges.old) == ["count"])
    #expect(text(new, ranges.new) == ["total"])
  }

  @Test func anInsertionMarksOnlyTheNewSide() throws {
    let old = "call(a, b)"
    let new = "call(a, b, c)"
    let ranges = try #require(WordDiff.ranges(old: old, new: new))
    #expect(ranges.old.isEmpty)
    #expect(text(new, ranges.new) == [", c"])
  }

  @Test func joinsNeighbouringChangedWords() throws {
    let ranges = try #require(WordDiff.ranges(old: "let x = compute(foo bar);", new: "let x = compute(baz qux);"))
    #expect(text("let x = compute(baz qux);", ranges.new) == ["baz qux"])
  }

  @Test func leavesUnrelatedRewritesAlone() {
    #expect(WordDiff.ranges(old: "return cache[key]", new: "print(\"hello, world\")") == nil)
    #expect(WordDiff.ranges(old: "same", new: "same") == nil)
    let long = String(repeating: "a ", count: 300)
    #expect(WordDiff.ranges(old: long, new: long + "b") == nil)
  }

  @Test func countsInUTF16AroundUnicode() throws {
    let old = "let 名前 = \"café\" // 👋"
    let new = "let 名前 = \"cafe\" // 👋"
    let ranges = try #require(WordDiff.ranges(old: old, new: new))
    #expect(text(old, ranges.old) == ["café"])
    #expect(text(new, ranges.new) == ["cafe"])
    // The emoji is two UTF-16 units; nothing after it is split.
    let emoji = try #require(WordDiff.ranges(old: "a 👋 b", new: "a 👋 c"))
    #expect(emoji.new == [5..<6])
  }

  @Test func pairsDeletionsWithTheAdditionsAfterThem() {
    let lines = [
      DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "func a() {"),
      DiffLine(kind: .deletion, oldNumber: 2, newNumber: nil, text: "  return one"),
      DiffLine(kind: .deletion, oldNumber: 3, newNumber: nil, text: "  // gone"),
      DiffLine(kind: .addition, oldNumber: nil, newNumber: 2, text: "  return two"),
      DiffLine(kind: .context, oldNumber: 4, newNumber: 3, text: "}"),
    ]
    let hunk = Hunk(
      id: 0, header: "", oldStart: 1, oldCount: 4, newStart: 1, newCount: 3, lines: lines, wordDiff: true)
    #expect(text(hunk.lines[1].text, hunk.lines[1].emphasis) == ["one"])
    #expect(text(hunk.lines[3].text, hunk.lines[3].emphasis) == ["two"])
    #expect(hunk.lines[2].emphasis.isEmpty)
    #expect(hunk.lines[0].emphasis.isEmpty)
    // The split rows carry the same marks.
    #expect(hunk.splitRows[1].right?.emphasis == hunk.lines[3].emphasis)

    let plain = Hunk(
      id: 0, header: "", oldStart: 1, oldCount: 4, newStart: 1, newCount: 3, lines: lines, wordDiff: false)
    #expect(plain.lines.allSatisfy { $0.emphasis.isEmpty })
  }

  @Test func movesRangesPastExpandedTabs() {
    // "\tx = 1": the tab becomes four spaces, so "1" moves from 5 to 8.
    #expect(WordDiff.displayRanges([5..<6], in: "\tx = 1", tabWidth: 4) == [8..<9])
    #expect(WordDiff.displayRanges([0..<1], in: "no tabs", tabWidth: 4) == [0..<1])
  }

  /// A big rewrite of similar lines stays fast: this is the cost the diff
  /// builder pays off the main thread.
  @Test func staysFastOnABigHunk() {
    var lines: [DiffLine] = []
    for i in 0..<5_000 {
      lines.append(
        DiffLine(kind: .deletion, oldNumber: i + 1, newNumber: nil, text: "    let value\(i) = compute(\(i), scale: 2)"))
    }
    for i in 0..<5_000 {
      lines.append(
        DiffLine(kind: .addition, oldNumber: nil, newNumber: i + 1, text: "    let value\(i) = compute(\(i), scale: 3)"))
    }
    let start = ContinuousClock.now
    let emphasized = WordDiff.emphasize(lines)
    let elapsed = ContinuousClock.now - start
    #expect(emphasized[0].emphasis.count == 1)
    print("word diff, 5,000 line pairs: \(elapsed)")
    #expect(elapsed < .seconds(1))

    // Past the cap, a hunk is left as it is.
    let huge = Array(repeating: lines[0], count: WordDiff.maxChangedLines / 2 + 1)
      + Array(repeating: lines[5_000], count: WordDiff.maxChangedLines / 2 + 1)
    #expect(WordDiff.emphasize(huge).allSatisfy { $0.emphasis.isEmpty })
  }

  // MARK: - Restore hunk

  @Test func restoresOneHunkOfTwoInTheWorkingCopy() async throws {
    let base = (1...12).map { "line \($0)" }.joined(separator: "\n") + "\n"
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["f.txt": base])
    var lines = (1...12).map { "line \($0)" }
    lines[1] = "line TWO"
    lines[10] = "line ELEVEN"
    lines.insert("inserted", at: 11)
    try fixture.write("f.txt", lines.joined(separator: "\n") + "\n")

    let repository = try await GitRepository.open(at: fixture.url)
    let file = try #require(try await repository.workingTreeDiff(staged: false, path: "f.txt").files.first)
    #expect(file.hunks.count == 2)
    let patch = try #require(Patch.restore(path: "f.txt", hunk: file.hunks[1]))
    try await repository.applyToWorkdir(patch)

    var expected = (1...12).map { "line \($0)" }
    expected[1] = "line TWO"
    let onDisk = try String(contentsOf: fixture.url.appendingPathComponent("f.txt"), encoding: .utf8)
    #expect(onDisk == expected.joined(separator: "\n") + "\n")
    // The index is untouched, and the other hunk is still there.
    #expect(try fixture.indexContents("f.txt") == base)
    let remaining = try #require(try await repository.workingTreeDiff(staged: false, path: "f.txt").files.first)
    #expect(remaining.hunks.count == 1)
    #expect(remaining.hunks[0].lines.contains { $0.text == "line TWO" })
  }

  @Test func restoresAHunkWithoutAFinalNewline() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["f.txt": "a\nb"])
    try fixture.write("f.txt", "a\nB\nc")
    let repository = try await GitRepository.open(at: fixture.url)
    let hunk = try #require(try await repository.workingTreeDiff(staged: false, path: "f.txt").files.first?.hunks.first)
    try await repository.applyToWorkdir(try #require(Patch.restore(path: "f.txt", hunk: hunk)))
    #expect(try String(contentsOf: fixture.url.appendingPathComponent("f.txt"), encoding: .utf8) == "a\nb")
  }
}
