import Foundation
import Testing

@testable import Glint

@Suite struct HunkEditTests {
  private func edit(start: Int, original: [String], text: String) -> HunkEdit {
    HunkEdit(path: "f.swift", fileName: "f.swift", startLine: start, original: original, text: text)
  }

  @Test func replacesTheLinesAndKeepsTheRest() {
    let content = "a\nb\nc\nd\n"
    let result = RepositorySession.applying(edit(start: 2, original: ["b", "c"], text: "B\nC\nextra"), to: content)
    #expect(result == "a\nB\nC\nextra\nd\n")
  }

  @Test func keepsCRLFAndAMissingFinalNewline() {
    let content = "a\r\nb\r\nc"
    let result = RepositorySession.applying(edit(start: 3, original: ["c"], text: "C"), to: content)
    #expect(result == "a\r\nb\r\nC")
  }

  @Test func refusesWhenTheFileMovedOn() {
    let content = "a\nchanged\nc\n"
    #expect(RepositorySession.applying(edit(start: 2, original: ["b"], text: "B"), to: content) == nil)
    #expect(RepositorySession.applying(edit(start: 3, original: ["c", "d"], text: "x"), to: content) == nil)
  }

  @Test func aTrailingNewlineInTheEditorIsNotAnExtraLine() {
    let result = RepositorySession.applying(edit(start: 1, original: ["a"], text: "A\n"), to: "a\nb\n")
    #expect(result == "A\nb\n")
  }
}
