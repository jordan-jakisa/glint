import Foundation
import Testing

@testable import Glint

/// Hunk and line staging, checked against real repositories: build the patch
/// from the diff Glint shows, apply it to the index, and compare what's staged.
@Suite struct PatchTests {
  private let base = (1...12).map { "line \($0)" }.joined(separator: "\n") + "\n"

  /// Two separate changes far enough apart to be two hunks.
  private func twoHunkFixture() throws -> FixtureRepository {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["f.txt": base])
    var lines = (1...12).map { "line \($0)" }
    lines[1] = "line TWO"
    lines[10] = "line ELEVEN"
    try fixture.write("f.txt", lines.joined(separator: "\n") + "\n")
    return fixture
  }

  private func unstagedFile(_ repository: GitRepository, _ path: String) async throws -> FileChange {
    let diff = try await repository.workingTreeDiff(staged: false, path: path)
    return try #require(diff.files.first)
  }

  private func stagedFile(_ repository: GitRepository, _ path: String) async throws -> FileChange {
    let diff = try await repository.workingTreeDiff(staged: true, path: path)
    return try #require(diff.files.first)
  }

  @Test func stagesOneHunkOfTwo() async throws {
    let fixture = try twoHunkFixture()
    let repository = try await GitRepository.open(at: fixture.url)
    let file = try await unstagedFile(repository, "f.txt")
    #expect(file.hunks.count == 2)

    let patch = try #require(
      Patch.make(path: "f.txt", isNewFile: false, hunk: file.hunks[1], selected: nil, unstage: false))
    try await repository.applyToIndex(patch)

    var expected = (1...12).map { "line \($0)" }
    expected[10] = "line ELEVEN"
    #expect(try fixture.indexContents("f.txt") == expected.joined(separator: "\n") + "\n")
    // The other hunk is still unstaged, the file on disk untouched.
    let remaining = try await unstagedFile(repository, "f.txt")
    #expect(remaining.hunks.count == 1)
    #expect(remaining.hunks[0].lines.contains { $0.text == "line TWO" })
  }

  @Test func stagesSelectedLinesOnly() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["f.txt": "a\nb\nc\n"])
    try fixture.write("f.txt", "a\nB1\nB2\nc\n")
    let repository = try await GitRepository.open(at: fixture.url)
    let hunk = try await unstagedFile(repository, "f.txt").hunks[0]
    // Lines: context a, -b, +B1, +B2, context c. Take the deletion and B1.
    let chosen = Set(hunk.lines.indices.filter { hunk.lines[$0].text == "b" || hunk.lines[$0].text == "B1" })

    let patch = try #require(Patch.make(path: "f.txt", isNewFile: false, hunk: hunk, selected: chosen, unstage: false))
    try await repository.applyToIndex(patch)
    #expect(try fixture.indexContents("f.txt") == "a\nB1\nc\n")
  }

  @Test func unselectedDeletionStaysInTheIndex() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["f.txt": "a\nb\nc\n"])
    try fixture.write("f.txt", "a\nnew\n")
    let repository = try await GitRepository.open(at: fixture.url)
    let hunk = try await unstagedFile(repository, "f.txt").hunks[0]
    let added = Set(hunk.lines.indices.filter { hunk.lines[$0].kind == .addition })

    let patch = try #require(Patch.make(path: "f.txt", isNewFile: false, hunk: hunk, selected: added, unstage: false))
    try await repository.applyToIndex(patch)
    // The removals of b and c weren't chosen, so they stay; only "new" lands.
    #expect(try fixture.indexContents("f.txt") == "a\nb\nc\nnew\n")
  }

  @Test func unstagesOneHunk() async throws {
    let fixture = try twoHunkFixture()
    try fixture.stage("f.txt")
    let repository = try await GitRepository.open(at: fixture.url)
    let file = try await stagedFile(repository, "f.txt")
    #expect(file.hunks.count == 2)

    let patch = try #require(
      Patch.make(path: "f.txt", isNewFile: false, hunk: file.hunks[0], selected: nil, unstage: true))
    try await repository.applyToIndex(patch)

    var expected = (1...12).map { "line \($0)" }
    expected[10] = "line ELEVEN"
    #expect(try fixture.indexContents("f.txt") == expected.joined(separator: "\n") + "\n")
  }

  @Test func unstagesSelectedLines() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["f.txt": "a\nb\nc\n"])
    try fixture.write("f.txt", "a\nB1\nB2\nc\n")
    try fixture.stage("f.txt")
    let repository = try await GitRepository.open(at: fixture.url)
    let hunk = try await stagedFile(repository, "f.txt").hunks[0]
    // Take B2 back out of the index; keep the rest staged.
    let chosen = Set(hunk.lines.indices.filter { hunk.lines[$0].text == "B2" })

    let patch = try #require(Patch.make(path: "f.txt", isNewFile: false, hunk: hunk, selected: chosen, unstage: true))
    try await repository.applyToIndex(patch)
    #expect(try fixture.indexContents("f.txt") == "a\nB1\nc\n")
  }

  @Test func stagesPartOfAnUntrackedFile() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["other.txt": "x\n"])
    try fixture.write("new.txt", "one\ntwo\nthree\n")
    let repository = try await GitRepository.open(at: fixture.url)
    let hunk = try await unstagedFile(repository, "new.txt").hunks[0]
    let chosen = Set(hunk.lines.indices.filter { hunk.lines[$0].text != "two" })

    let patch = try #require(Patch.make(path: "new.txt", isNewFile: true, hunk: hunk, selected: chosen, unstage: false))
    try await repository.applyToIndex(patch)
    #expect(try fixture.indexContents("new.txt") == "one\nthree\n")
  }

  @Test func handlesAMissingFinalNewline() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["f.txt": "a\nb"])
    try fixture.write("f.txt", "a\nb\nc")
    let repository = try await GitRepository.open(at: fixture.url)
    let hunk = try await unstagedFile(repository, "f.txt").hunks[0]

    let patch = try #require(Patch.make(path: "f.txt", isNewFile: false, hunk: hunk, selected: nil, unstage: false))
    try await repository.applyToIndex(patch)
    #expect(try fixture.indexContents("f.txt") == "a\nb\nc")
  }

  @Test func noChangedLinesMeansNoPatch() {
    let hunk = Hunk(
      id: 0, header: "", oldStart: 1, oldCount: 1, newStart: 1, newCount: 1,
      lines: [DiffLine(kind: .context, oldNumber: 1, newNumber: 1, text: "a")])
    #expect(Patch.make(path: "f", isNewFile: false, hunk: hunk, selected: [], unstage: false) == nil)
  }
}
