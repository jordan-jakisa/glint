import Foundation
import Testing

@testable import Glint

@Suite struct BlameTests {
  private let first = "1111111111111111111111111111111111111111"
  private let second = "2222222222222222222222222222222222222222"
  private let zero = String(repeating: "0", count: 40)

  @Test func parsesPorcelainWithRepeatedCommitsAndUncommittedLines() {
    let porcelain = """
      \(first) 1 1 2
      author Ada Lovelace
      author-mail <ada@example.com>
      author-time 1700000000
      author-tz +0000
      committer Ada Lovelace
      committer-mail <ada@example.com>
      committer-time 1700000000
      committer-tz +0000
      summary Start the engine
      boundary
      filename engine.swift
      \tlet a = 1
      \(first) 2 2
      \tlet b = 2
      \(second) 3 3 1
      author Grace Hopper
      author-mail <grace@example.com>
      author-time 1700086400
      author-tz -0500
      committer Grace Hopper
      committer-mail <grace@example.com>
      committer-time 1700086400
      committer-tz -0500
      summary Fix the bug
      previous \(first) engine.swift
      filename engine.swift
      \tlet c = 3
      \(zero) 4 4 1
      author Not Committed Yet
      author-mail <not.committed.yet>
      author-time 1700090000
      author-tz +0000
      committer Not Committed Yet
      committer-mail <not.committed.yet>
      committer-time 1700090000
      committer-tz +0000
      summary Version of engine.swift from engine.swift
      previous \(second) engine.swift
      filename engine.swift
      \tlet d = 4
      \(first) 3 5 1
      filename engine.swift
      \t// summary author 1 2 3

      """
    let blame = Blame.parse(porcelain: porcelain)
    #expect(blame.lines.count == 5)
    #expect(blame.line(1)?.commit.author == "Ada Lovelace")
    #expect(blame.line(1)?.commit.authorMail == "<ada@example.com>")
    #expect(blame.line(1)?.commit.summary == "Start the engine")
    #expect(blame.line(1)?.commit.date == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(blame.line(2)?.commit.id == first)
    #expect(blame.line(2)?.text == "let b = 2")
    #expect(blame.line(3)?.commit.summary == "Fix the bug")
    #expect(blame.line(3)?.commit.shortID == "2222222")
    #expect(blame.line(4)?.commit.isCommitted == false)
    #expect(blame.line(5)?.commit.id == first)
    #expect(blame.line(5)?.text == "// summary author 1 2 3")
    #expect(blame.line(0) == nil)
    #expect(blame.line(6) == nil)
  }

  @Test func matchingIgnoresCarriageReturns() {
    let line = BlameLine(commit: .uncommitted, text: "let a = 1\r")
    #expect(line.matches("let a = 1"))
    #expect(!line.matches("let a = 2"))
  }

  @Test func textForTheGutterAndInline() {
    let commit = BlameCommit(
      id: first, author: "Bartholomew Smith", authorMail: "<b@example.com>",
      date: Date(timeIntervalSince1970: 0), summary: "Tidy up")
    #expect(commit.shortAuthor(limit: 8) == "Barthol\u{2026}")
    #expect(BlameCommit.uncommitted.inlineText() == "Not committed yet")
    let now = Date(timeIntervalSince1970: 3 * 86_400)
    #expect(commit.inlineText(now: now) == "Bartholomew Smith, 3 days ago \u{00B7} Tidy up")
  }

  @Test func relativeDatesStayShort() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    func ago(_ seconds: Double) -> String { BlameDate.text(for: now.addingTimeInterval(-seconds), now: now) }
    #expect(ago(10) == "just now")
    #expect(ago(5 * 60) == "5 min ago")
    #expect(ago(3 * 3600) == "3 hr ago")
    #expect(ago(86_400) == "1 day ago")
    #expect(ago(13 * 86_400) == "13 days ago")
    #expect(ago(21 * 86_400) == "3 wk ago")
    #expect(ago(100 * 86_400) == "3 mo ago")
    #expect(ago(800 * 86_400) == "2 yr ago")
    #expect(ago(13 * 86_400).count <= BlameDate.maxLength)
  }

  @Test func blamesARealRepository() async throws {
    let fixture = try FixtureRepository()
    let base = try fixture.commit("First", files: ["a.txt": "one\ntwo\n"])
    let next = try fixture.commit("Second", files: ["a.txt": "one\nTWO\nthree\n"])
    try fixture.write("a.txt", "one\nTWO\nthree\nfour\n")
    let git = SystemGit(directory: fixture.url)

    let working = try await RepositorySession.blame(of: "a.txt", at: .workingTree, git: git)
    #expect(working.lines.count == 4)
    #expect(working.line(1)?.commit.id == base)
    #expect(working.line(1)?.commit.author == "Test Author")
    #expect(working.line(2)?.commit.id == next)
    #expect(working.line(2)?.commit.summary == "Second")
    #expect(working.line(4)?.commit.isCommitted == false)
    #expect(working.line(4)?.text == "four")

    let old = try await RepositorySession.blame(of: "a.txt", at: .commit(base), git: git)
    #expect(old.lines.count == 2)
    #expect(old.line(2)?.text == "two")
    #expect(old.line(2)?.commit.summary == "First")

    // Staged: blamed from the index, not the file on disk.
    try fixture.write("a.txt", "zero\none\nTWO\nthree\n")
    try fixture.stage("a.txt")
    try fixture.write("a.txt", "something else entirely\n")
    let staged = try await RepositorySession.blame(of: "a.txt", at: .index, git: git)
    #expect(staged.lines.count == 4)
    #expect(staged.line(1)?.commit.isCommitted == false)
    #expect(staged.line(2)?.commit.id == base)
    #expect(staged.line(3)?.commit.id == next)
  }
}
