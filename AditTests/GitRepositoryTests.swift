import Foundation
import Testing

@testable import Adit

@Suite struct GitRepositoryTests {
  @Test func readsBranchAndEmptyState() async throws {
    let fixture = try FixtureRepository()
    let repository = try await GitRepository.open(at: fixture.url)

    let empty = await repository.info()
    #expect(empty.isEmpty)
    #expect(try await repository.firstCommits(limit: 10).isEmpty)

    try fixture.commit("First", files: ["a.txt": "a\n"])
    let info = await repository.info()
    #expect(!info.isEmpty)
    #expect(info.branch == "main" || info.branch == "master")
  }

  @Test func opensTheRepositoryAboveASubfolder() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("First", files: ["sub/dir/a.txt": "a\n"])
    let repository = try await GitRepository.open(at: fixture.url.appendingPathComponent("sub/dir"))
    #expect(repository.url.resolvingSymlinksInPath() == fixture.url.resolvingSymlinksInPath())
  }

  @Test func rejectsAFolderThatIsNotARepository() async throws {
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent("adit-not-a-repo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    await #expect(throws: GitError.self) {
      _ = try await GitRepository.open(at: folder)
    }
  }

  @Test func pagesThroughHistoryNewestFirst() async throws {
    let fixture = try FixtureRepository()
    var ids: [String] = []
    for n in 1...25 {
      ids.append(try fixture.commit("Commit \(n)\n\nBody text.", files: ["n.txt": "\(n)\n"]))
    }
    let repository = try await GitRepository.open(at: fixture.url)

    let first = try await repository.firstCommits(limit: 10)
    let second = try await repository.moreCommits(limit: 10)
    let third = try await repository.moreCommits(limit: 10)
    let done = try await repository.moreCommits(limit: 10)

    #expect(first.count == 10)
    #expect(second.count == 10)
    #expect(third.count == 5)
    #expect(done.isEmpty)
    #expect((first + second + third).map(\.id) == ids.reversed())
    #expect(first[0].summary == "Commit 25")
    #expect(first[0].authorName == "Test Author")
    #expect(first[0].shortID == String(ids[24].prefix(7)))
    #expect(await repository.headCommitID() == ids[24])
  }

  @Test func diffsAModifiedFileWithCorrectLineNumbers() async throws {
    let fixture = try FixtureRepository()
    let before = (1...10).map { "line \($0)" }.joined(separator: "\n") + "\n"
    var lines = (1...10).map { "line \($0)" }
    lines[4] = "line five"  // replace line 5
    lines.insert("inserted", at: 8)  // new line 9
    let after = lines.joined(separator: "\n") + "\n"

    try fixture.commit("Base", files: ["file.txt": before])
    let id = try fixture.commit("Change", files: ["file.txt": after])
    let repository = try await GitRepository.open(at: fixture.url)
    let diff = try await repository.diff(commitID: id)

    #expect(diff.files.count == 1)
    let file = try #require(diff.files.first)
    #expect(file.status == .modified)
    #expect(file.path == "file.txt")
    #expect(file.additions == 2)
    #expect(file.deletions == 1)
    #expect(file.hunks.count == 1)

    let hunk = try #require(file.hunks.first)
    #expect(hunk.oldStart == 2)
    #expect(hunk.newStart == 2)
    #expect(hunk.header.hasPrefix("@@ -2,"))

    let deletion = try #require(hunk.lines.first { $0.kind == .deletion })
    #expect(deletion.text == "line 5")
    #expect(deletion.oldNumber == 5)
    #expect(deletion.newNumber == nil)

    let additions = hunk.lines.filter { $0.kind == .addition }
    #expect(additions.map(\.text) == ["line five", "inserted"])
    #expect(additions.map(\.newNumber) == [5, 9])
    #expect(additions.allSatisfy { $0.oldNumber == nil })

    // Context lines carry both numbers, offset by the insertion after it.
    let context = try #require(hunk.lines.last { $0.kind == .context })
    #expect(context.text == "line 10")
    #expect(context.oldNumber == 10)
    #expect(context.newNumber == 11)
  }

  @Test func diffsRootCommitAndDeletion() async throws {
    let fixture = try FixtureRepository()
    let root = try fixture.commit("Root", files: ["a.txt": "one\ntwo\n", "b/c.txt": "c\n"])
    let removal = try fixture.commit("Remove", files: ["a.txt": nil])
    let repository = try await GitRepository.open(at: fixture.url)

    let rootDiff = try await repository.diff(commitID: root)
    #expect(rootDiff.files.map(\.path) == ["a.txt", "b/c.txt"])
    #expect(rootDiff.files.allSatisfy { $0.status == .added && $0.oldPath == nil })
    #expect(rootDiff.additions == 3)

    let removalDiff = try await repository.diff(commitID: removal)
    let deleted = try #require(removalDiff.files.first)
    #expect(deleted.status == .deleted)
    #expect(deleted.newPath == nil)
    #expect(deleted.path == "a.txt")
    #expect(deleted.hunks.first?.lines.map(\.oldNumber) == [1, 2])
  }

  @Test func marksMissingNewlineAndBinaryFiles() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["text.txt": "a\nb\n"])
    let id = try fixture.commit(
      "Change",
      data: ["text.txt": Data("a\nc".utf8), "image.bin": Data([0, 1, 2, 0, 255, 0, 3])])
    let repository = try await GitRepository.open(at: fixture.url)
    let diff = try await repository.diff(commitID: id)

    let binary = try #require(diff.files.first { $0.path == "image.bin" })
    #expect(binary.isBinary)
    #expect(binary.hunks.isEmpty)

    let text = try #require(diff.files.first { $0.path == "text.txt" })
    let kinds = text.hunks.flatMap(\.lines).map(\.kind)
    #expect(kinds == [.context, .deletion, .addition, .noNewline])
  }

  @Test func handlesCRLFAndNonUTF8() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["w.txt": "x\r\n"])
    let id = try fixture.commit(
      "Change", data: ["w.txt": Data("y\r\n".utf8), "latin.txt": Data([0x63, 0x61, 0x66, 0xE9, 0x0A])])
    let repository = try await GitRepository.open(at: fixture.url)
    let diff = try await repository.diff(commitID: id)

    let crlf = try #require(diff.files.first { $0.path == "w.txt" })
    #expect(crlf.hunks.first?.lines.map(\.text) == ["x", "y"])
    // Invalid UTF-8 decodes with replacement characters instead of failing.
    let latin = try #require(diff.files.first { $0.path == "latin.txt" })
    #expect(latin.hunks.first?.lines.first?.text == "caf\u{FFFD}")
  }
}

@Suite struct StatusTests {
  @Test func splitsStagedUnstagedAndUntracked() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["tracked.txt": "one\n", "gone.txt": "bye\n"])
    let repository = try await GitRepository.open(at: fixture.url)
    #expect(try await repository.status().isClean)

    try fixture.write("tracked.txt", "one\ntwo\n")
    try fixture.write("new/untracked.txt", "hi\n")
    try fixture.delete("gone.txt")
    try fixture.write("staged.txt", "s\n")
    try fixture.stage("staged.txt")

    let status = try await repository.status()
    #expect(status.staged == [ChangedFile(path: "staged.txt", kind: .added)])
    #expect(
      Set(status.unstaged) == [
        ChangedFile(path: "tracked.txt", kind: .modified),
        ChangedFile(path: "new/untracked.txt", kind: .untracked),
        ChangedFile(path: "gone.txt", kind: .deleted),
      ])
  }

  @Test func partlyStagedFileAppearsInBothGroups() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n"])
    try fixture.write("a.txt", "1\n2\n")
    try fixture.stage("a.txt")
    try fixture.write("a.txt", "1\n2\n3\n")

    let status = try await GitRepository.open(at: fixture.url).status()
    #expect(status.staged.map(\.path) == ["a.txt"])
    #expect(status.unstaged.map(\.path) == ["a.txt"])
  }

  @Test func seesIndexChangesMadeByOtherTools() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n"])
    let repository = try await GitRepository.open(at: fixture.url)
    #expect(try await repository.status().isClean)

    // Another process stages a change after Adit has read the index.
    try fixture.write("a.txt", "2\n")
    try fixture.stage("a.txt")
    #expect(try await repository.status().staged.map(\.path) == ["a.txt"])
  }
}
