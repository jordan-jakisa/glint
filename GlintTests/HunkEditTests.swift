import Foundation
import Testing

@testable import Glint

@MainActor @Suite struct HunkEditTests {
  private func file(_ content: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString).appendingPathExtension("swift")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  private func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

  @Test func replacesTheLinesAndKeepsTheRest() throws {
    let url = try file("a\nb\nc\nd\n")
    let edit = LiveEdit(url: url, content: try read(url), start: 1, count: 2)
    #expect(edit.text == "b\nc")
    edit.text = "B\nC\nextra"
    try edit.save()
    #expect(try read(url) == "a\nB\nC\nextra\nd\n")
  }

  @Test func keepsCRLFAndAMissingFinalNewline() throws {
    let url = try file("a\r\nb\r\nc")
    let edit = LiveEdit(url: url, content: try read(url), start: 2, count: 1)
    edit.text = "C"
    try edit.save()
    #expect(try read(url) == "a\r\nb\r\nC")
  }

  @Test func aTrailingNewlineInTheEditorIsNotAnExtraLine() throws {
    let url = try file("a\nb\n")
    let edit = LiveEdit(url: url, content: try read(url), start: 0, count: 1)
    edit.text = "A\n"
    try edit.save()
    #expect(try read(url) == "A\nb\n")
  }

  @Test func changesOnDiskAppearWhileYouType() throws {
    let url = try file("one\ntwo\nthree\nfour\nfive\n")
    let edit = LiveEdit(url: url, content: try read(url), start: 1, count: 3)
    edit.text = "TWO\nthree\nfour"
    // Something else adds a line above and edits one you haven't touched.
    try "zero\none\ntwo\nthree\nFOUR\nfive\n".write(to: url, atomically: true, encoding: .utf8)
    edit.syncFromDisk()
    #expect(edit.text == "TWO\nthree\nFOUR")
    #expect(edit.firstLineNumber == 3)
    try edit.save()
    #expect(try read(url) == "zero\none\nTWO\nthree\nFOUR\nfive\n")
  }

  @Test func savingMergesWhatChangedSinceTheLastLook() throws {
    let url = try file("a\nb\nc\n")
    let edit = LiveEdit(url: url, content: try read(url), start: 1, count: 1)
    edit.text = "B"
    try "a\nb\nc\nd\n".write(to: url, atomically: true, encoding: .utf8)
    try edit.save()
    #expect(try read(url) == "a\nB\nc\nd\n")
  }

  @Test func whenBothChangeTheSameLineYoursWin() throws {
    let url = try file("a\nb\nc\n")
    let edit = LiveEdit(url: url, content: try read(url), start: 0, count: 3)
    edit.text = "a\nmine\nc"
    try "a\ntheirs\nc\n".write(to: url, atomically: true, encoding: .utf8)
    edit.syncFromDisk()
    #expect(edit.text == "a\nmine\nc")
    #expect(edit.note?.contains("Yours are kept") == true)
  }
}

@Suite struct LineMergeTests {
  @Test func takesEachSidesSeparateChanges() {
    let result = LineMerge.merge(base: ["a", "b", "c"], ours: ["a", "B", "c"], theirs: ["a", "b", "c", "d"])
    #expect(result.lines == ["a", "B", "c", "d"])
    #expect(!result.conflicted)
  }

  @Test func sameChangeOnBothSidesIsNotAConflict() {
    let result = LineMerge.merge(base: ["a", "b"], ours: ["a", "x"], theirs: ["a", "x"])
    #expect(result.lines == ["a", "x"])
    #expect(!result.conflicted)
  }

  @Test func mapsBoundariesThroughInsertions() {
    let result = LineMerge.merge(base: ["a", "b"], ours: ["a", "b"], theirs: ["new", "a", "b"])
    #expect(result.lower[1] == 2)
    #expect(result.upper[2] == 3)
  }
}

@Suite struct SyntaxTests {
  private func kinds(_ text: String, _ path: String) -> [String: SyntaxKind] {
    let language = SyntaxLanguage.forPath(path)!
    var state = SyntaxState.normal
    let utf16 = Array(text.utf16)
    var result: [String: SyntaxKind] = [:]
    for span in Syntax.spans(in: text, language: language, state: &state) {
      result[String(decoding: utf16[span.range], as: UTF16.self)] = span.kind
    }
    return result
  }

  @Test func typeScript() {
    let found = kinds(
      "/** Doc. */\nexport const LIMIT = 15_000; // note\nconst x = { key: \"v\" };\nparsed.data.filter(f(true));",
      "a.ts")
    #expect(found["/** Doc. */"] == .docComment)
    #expect(found["export"] == .keyword)
    #expect(found["LIMIT"] == .constant)
    #expect(found["15_000"] == .number)
    #expect(found["// note"] == .comment)
    #expect(found["key"] == .property)
    #expect(found["\"v\""] == .string)
    #expect(found["data"] == .property)
    #expect(found["filter"] == .function)
    #expect(found["true"] == .boolean)
  }

  @Test func blockCommentsCarryOverLines() {
    let language = SyntaxLanguage.forPath("x.swift")!
    var state = SyntaxState.normal
    _ = Syntax.spans(in: "let a = 1 /* open", language: language, state: &state)
    #expect(state == .blockComment(doc: false))
    let spans = Syntax.spans(in: "still */ let", language: language, state: &state)
    #expect(spans.first == SyntaxSpan(range: 0..<8, kind: .comment))
    #expect(state == .normal)
  }

  @Test func diffLinesInsideDocComments() {
    let spans = Syntax.spans(inLine: "   * Reads the cookie.", language: SyntaxLanguage.forPath("a.ts")!)
    #expect(spans.first?.kind == .docComment)
  }

  @Test func languagesByName() {
    #expect(SyntaxLanguage.forPath("src/Dockerfile")?.name == "Dockerfile")
    #expect(SyntaxLanguage.forPath("Makefile")?.name == "Makefile")
    #expect(SyntaxLanguage.forPath("a/b.PY")?.name == "Python")
    #expect(SyntaxLanguage.forPath("README") == nil)
  }

  @Test func yamlKeysAndComments() {
    let found = kinds("name: glint # the app\n- item: 3", "a.yml")
    #expect(found["name"] == .property)
    #expect(found["# the app"] == .comment)
    #expect(found["item"] == .property)
    #expect(found["3"] == .number)
  }
}

@MainActor @Suite struct AutosaveTests {
  private func file(_ content: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ts")
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  @Test func savesAfterYouPauseTyping() async throws {
    let url = try file("a\nb\n")
    let edit = LiveEdit(url: url, content: "a\nb\n", start: 0, count: 2, wholeFile: true)
    edit.autosaveDelay = .milliseconds(50)
    edit.text = "a\nB"
    try await Task.sleep(for: .milliseconds(300))
    #expect(try String(contentsOf: url, encoding: .utf8) == "a\nB\n")
    #expect(!edit.hasUnsavedChanges)
  }

  @Test func changesFromDiskDontTriggerASave() async throws {
    let url = try file("a\n")
    let edit = LiveEdit(url: url, content: "a\n", start: 0, count: 1, wholeFile: true)
    edit.autosaveDelay = .milliseconds(50)
    try "b\n".write(to: url, atomically: true, encoding: .utf8)
    edit.syncFromDisk()
    #expect(edit.text == "b")
    try await Task.sleep(for: .milliseconds(300))
    #expect(try String(contentsOf: url, encoding: .utf8) == "b\n")
  }

  @Test func withoutADelayNothingSavesOnItsOwn() async throws {
    let url = try file("a\n")
    let edit = LiveEdit(url: url, content: "a\n", start: 0, count: 1)
    edit.text = "changed"
    try await Task.sleep(for: .milliseconds(200))
    #expect(try String(contentsOf: url, encoding: .utf8) == "a\n")
  }
}
