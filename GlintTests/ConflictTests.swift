import Foundation
import Testing

@testable import Glint

@Suite struct ConflictTests {
  private let standard = """
    top
    <<<<<<< HEAD
    ours 1
    ours 2
    =======
    theirs
    >>>>>>> feature/login
    bottom

    """

  @Test func parsesStandardMarkers() throws {
    let regions = Conflict.parse(standard)
    #expect(regions.count == 1)
    let region = try #require(regions.first)
    #expect(region.lines == 1..<7)
    #expect(region.current == ["ours 1", "ours 2"])
    #expect(region.incoming == ["theirs"])
    #expect(region.base == nil)
    #expect(region.currentLabel == "HEAD")
    #expect(region.incomingLabel == "feature/login")
  }

  @Test func parsesDiff3MarkersAndKeepsTheBaseApart() throws {
    let content = "<<<<<<< ours\na\n||||||| merged common ancestors\nbase\n=======\nb\n>>>>>>> theirs\n"
    let region = try #require(Conflict.parse(content).first)
    #expect(region.current == ["a"])
    #expect(region.base == ["base"])
    #expect(region.incoming == ["b"])
    #expect(Conflict.resolving(region: region, choice: .both, in: content) == "a\nb\n")
  }

  @Test func parsesSeveralRegions() {
    let content = "<<<<<<< HEAD\n1\n=======\n2\n>>>>>>> x\nmid\n<<<<<<< HEAD\n3\n=======\n>>>>>>> x\n"
    let regions = Conflict.parse(content)
    #expect(regions.map(\.index) == [0, 1])
    #expect(regions.map(\.lines) == [0..<5, 6..<10])
    #expect(regions[1].current == ["3"])
    #expect(regions[1].incoming == [])
  }

  @Test func parsesCRLF() throws {
    let content = "a\r\n<<<<<<< HEAD\r\nx\r\n=======\r\ny\r\n>>>>>>> main\r\nb\r\n"
    let region = try #require(Conflict.parse(content).first)
    #expect(region.current == ["x"])
    #expect(region.incoming == ["y"])
    #expect(region.incomingLabel == "main")
    #expect(Conflict.resolving(region: region, choice: .incoming, in: content) == "a\r\ny\r\nb\r\n")
  }

  @Test func ignoresAnUnfinishedRegionAndLookalikes() {
    #expect(Conflict.parse("<<<<<<< HEAD\na\n=======\nb\n").isEmpty)
    #expect(Conflict.parse("<<<<<<<< not a marker\n=======\n>>>>>>> x\n").isEmpty)
  }

  @Test func resolvesEachChoice() throws {
    let region = try #require(Conflict.parse(standard).first)
    #expect(Conflict.resolving(region: region, choice: .current, in: standard) == "top\nours 1\nours 2\nbottom\n")
    #expect(Conflict.resolving(region: region, choice: .incoming, in: standard) == "top\ntheirs\nbottom\n")
    #expect(
      Conflict.resolving(region: region, choice: .both, in: standard) == "top\nours 1\nours 2\ntheirs\nbottom\n")
  }

  @Test func resolvingOneRegionLeavesTheOthers() throws {
    let content = "<<<<<<< HEAD\n1\n=======\n2\n>>>>>>> x\nmid\n<<<<<<< HEAD\n3\n=======\n4\n>>>>>>> x"
    let first = try #require(Conflict.parse(content).first)
    let once = Conflict.resolving(region: first, choice: .incoming, in: content)
    #expect(once == "2\nmid\n<<<<<<< HEAD\n3\n=======\n4\n>>>>>>> x")
    let second = try #require(Conflict.parse(once).first)
    #expect(Conflict.resolving(region: second, choice: .current, in: once) == "2\nmid\n3")
  }

  @Test func refusesWhenTheFileChanged() throws {
    let region = try #require(Conflict.parse(standard).first)
    let changed = standard.replacingOccurrences(of: "top", with: "edited")
    #expect(RepositorySession.resolving(region, as: .current, loaded: standard, current: changed) == nil)
    #expect(
      RepositorySession.resolving(region, as: .current, loaded: standard, current: standard)
        == "top\nours 1\nours 2\nbottom\n")
    // Markers no longer where they were found: the text is left alone.
    #expect(Conflict.resolving(region: region, choice: .current, in: "top\n") == "top\n")
  }

  @Test func foldsLongContextAroundRegions() {
    let head = (1...10).map { "h\($0)" }
    let tail = (1...10).map { "t\($0)" }
    let content = (head + ["<<<<<<< HEAD", "a", "=======", "b", ">>>>>>> x"] + tail).joined(separator: "\n") + "\n"
    let segments = ConflictView.segments(of: ConflictDocument(path: "f", content: content))
    let kinds = segments.map { segment -> String in
      switch segment.kind {
      case .context(let start, let lines): "context \(start) \(lines.count)"
      case .gap(let count): "gap \(count)"
      case .region: "region"
      }
    }
    #expect(kinds == ["gap 7", "context 7 3", "region", "context 15 3", "gap 7"])
  }
}
