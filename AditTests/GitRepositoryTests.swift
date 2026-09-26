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

@Suite struct WorkingTreeDiffTests {
  @Test func unstagedStagedAndUntracked() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n2\n3\n", "b.txt": "b\n"])
    try fixture.write("a.txt", "1\ntwo\n3\n")
    try fixture.stage("a.txt")
    try fixture.write("a.txt", "1\ntwo\n3\nfour\n")
    try fixture.write("new.txt", "fresh\n")
    let repository = try await GitRepository.open(at: fixture.url)

    let staged = try await repository.workingTreeDiff(staged: true, path: "a.txt")
    #expect(staged.source == .workingTree(staged: true, path: "a.txt"))
    let stagedLines = staged.files.flatMap(\.hunks).flatMap(\.lines).filter { $0.kind != .context }
    #expect(stagedLines.map(\.text) == ["2", "two"])

    let unstaged = try await repository.workingTreeDiff(staged: false, path: "a.txt")
    #expect(unstaged.files.count == 1)
    let added = unstaged.files[0].hunks.flatMap(\.lines).filter { $0.kind == .addition }
    #expect(added.map(\.text) == ["four"])
    #expect(added.map(\.newNumber) == [4])

    let untracked = try await repository.workingTreeDiff(staged: false, path: "new.txt")
    #expect(untracked.files.first?.status == .added)
    #expect(untracked.files.first?.hunks.first?.lines.map(\.text) == ["fresh"])

    let everything = try await repository.workingTreeDiff(staged: false, path: nil)
    #expect(Set(everything.files.map(\.path)) == ["a.txt", "new.txt"])
  }

  @Test func stagedDiffInAnEmptyRepository() async throws {
    let fixture = try FixtureRepository()
    try fixture.write("first.txt", "hello\n")
    try fixture.stage("first.txt")
    let diff = try await GitRepository.open(at: fixture.url).workingTreeDiff(staged: true, path: nil)
    #expect(diff.files.map(\.path) == ["first.txt"])
    #expect(diff.files.first?.status == .added)
  }

  @Test func pathWithSpecialCharactersMatchesExactly() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["[x]*.txt": "1\n", "ax.txt": "1\n"])
    try fixture.write("[x]*.txt", "2\n")
    try fixture.write("ax.txt", "2\n")
    let diff = try await GitRepository.open(at: fixture.url).workingTreeDiff(staged: false, path: "[x]*.txt")
    #expect(diff.files.map(\.path) == ["[x]*.txt"])
  }
}

@Suite struct StagingTests {
  @Test func stageAndUnstageFiles() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n", "gone.txt": "x\n"])
    try fixture.write("a.txt", "2\n")
    try fixture.write("new.txt", "n\n")
    try fixture.delete("gone.txt")
    let repository = try await GitRepository.open(at: fixture.url)

    try await repository.stage(["a.txt", "new.txt", "gone.txt"])
    var status = try await repository.status()
    #expect(Set(status.staged) == [
      ChangedFile(path: "a.txt", kind: .modified),
      ChangedFile(path: "new.txt", kind: .added),
      ChangedFile(path: "gone.txt", kind: .deleted),
    ])
    #expect(status.unstaged.isEmpty)

    try await repository.unstage(["a.txt", "new.txt", "gone.txt"])
    status = try await repository.status()
    #expect(status.staged.isEmpty)
    #expect(Set(status.unstaged.map(\.path)) == ["a.txt", "new.txt", "gone.txt"])
    #expect(status.unstaged.first { $0.path == "new.txt" }?.kind == .untracked)
  }

  @Test func stageAllIncludesDeletions() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n", "b.txt": "2\n"])
    try fixture.write("a.txt", "changed\n")
    try fixture.delete("b.txt")
    try fixture.write("dir/c.txt", "c\n")
    let repository = try await GitRepository.open(at: fixture.url)

    try await repository.stageAll()
    let status = try await repository.status()
    #expect(status.unstaged.isEmpty)
    #expect(Set(status.staged.map(\.path)) == ["a.txt", "b.txt", "dir/c.txt"])
  }

  @Test func unstageInAnEmptyRepository() async throws {
    let fixture = try FixtureRepository()
    try fixture.write("first.txt", "1\n")
    let repository = try await GitRepository.open(at: fixture.url)
    try await repository.stage(["first.txt"])
    #expect(try await repository.status().staged.map(\.path) == ["first.txt"])
    try await repository.unstage(["first.txt"])
    let status = try await repository.status()
    #expect(status.staged.isEmpty)
    #expect(status.unstaged.map(\.kind) == [.untracked])
  }

  @Test func reportsAHeldIndexLock() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n"])
    try fixture.write("a.txt", "2\n")
    try fixture.write(".git/index.lock", "")
    let repository = try await GitRepository.open(at: fixture.url)
    await #expect(throws: GitError.self) { try await repository.stage(["a.txt"]) }
  }
}

@Suite struct DiscardTests {
  @Test func restoresTrackedFilesAndKeepsStagedChanges() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n", "b.txt": "b\n"])
    try fixture.write("a.txt", "staged\n")
    try fixture.stage("a.txt")
    try fixture.write("a.txt", "unstaged on top\n")
    try fixture.delete("b.txt")
    let repository = try await GitRepository.open(at: fixture.url)

    try await repository.discard(["a.txt", "b.txt"])
    let a = try String(contentsOf: fixture.url.appendingPathComponent("a.txt"), encoding: .utf8)
    #expect(a == "staged\n")
    #expect(FileManager.default.fileExists(atPath: fixture.url.appendingPathComponent("b.txt").path))
    let status = try await repository.status()
    #expect(status.unstaged.isEmpty)
    #expect(status.staged.map(\.path) == ["a.txt"])
  }
}

@Suite struct CommitTests {
  @Test func systemGitCommitsStagedChanges() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n"])
    try fixture.write("a.txt", "2\n")
    try fixture.stage("a.txt")
    let git = SystemGit(directory: fixture.url)
    _ = try await git.run(["-c", "user.name=Test", "-c", "user.email=t@example.com", "commit", "-F", "-"], input: "Change a\n\nBody.")
    #expect(try fixture.headSummary() == "Change a")
    #expect(try await GitRepository.open(at: fixture.url).status().isClean)
  }

  @Test func systemGitFailureCarriesGitsMessage() async throws {
    let fixture = try FixtureRepository()
    let git = SystemGit(directory: fixture.url)
    await #expect(throws: SystemGit.Failure.self) {
      _ = try await git.run(["checkout", "no-such-branch"])
    }
  }

  @Test func undoLastCommitKeepsChangesStaged() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n"])
    try fixture.commit("Second\n\nWith a body.", files: ["a.txt": "2\n"])
    let repository = try await GitRepository.open(at: fixture.url)

    let message = try await repository.undoLastCommit()
    #expect(message.hasPrefix("Second"))
    #expect(try fixture.headSummary() == "Base")
    let status = try await repository.status()
    #expect(status.staged.map(\.path) == ["a.txt"])
    #expect(status.unstaged.isEmpty)
  }

  @Test func undoRefusesTheFirstCommit() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Only", files: ["a.txt": "1\n"])
    let repository = try await GitRepository.open(at: fixture.url)
    await #expect(throws: GitError.self) { _ = try await repository.undoLastCommit() }
  }
}

@Suite struct BranchTests {
  @Test func listsBranchesAndSwitches() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n"])
    let git = SystemGit(directory: fixture.url)
    _ = try await git.run(["branch", "feature"])
    let repository = try await GitRepository.open(at: fixture.url)

    var branches = try await repository.branches()
    #expect(Set(branches.map(\.name)) == ["feature", branches.first { $0.isCurrent }!.name])
    #expect(branches.filter(\.isCurrent).count == 1)

    _ = try await git.run(["switch", "feature"])
    branches = try await repository.branches()
    #expect(branches.first { $0.isCurrent }?.name == "feature")
    #expect(await repository.info().branch == "feature")
  }

  @Test func remoteBranchSwitchNameDropsTheRemote() {
    let branch = Branch(name: "origin/feature/x", isRemote: true, isCurrent: false, date: .now)
    #expect(branch.switchName == "feature/x")
  }
}

@Suite struct RemoteTests {
  @Test func tracksAheadAndBehindThroughARealRemote() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n"])
    let remote = FileManager.default.temporaryDirectory.appendingPathComponent("adit-remote-\(UUID().uuidString).git")
    defer { try? FileManager.default.removeItem(at: remote) }
    let git = SystemGit(directory: fixture.url)
    _ = try await SystemGit(directory: FileManager.default.temporaryDirectory).run(["init", "--bare", "-q", remote.path])
    _ = try await git.run(["remote", "add", "origin", remote.path])

    let repository = try await GitRepository.open(at: fixture.url)
    var sync = await repository.syncStatus()
    #expect(sync.upstream == nil)
    #expect(sync.hasRemotes)
    #expect(await repository.defaultRemote() == "origin")

    let branch = try #require(await repository.info().branch)
    _ = try await git.run(["push", "-q", "--set-upstream", "origin", branch])
    sync = await repository.syncStatus()
    #expect(sync.upstream == "origin/\(branch)")
    #expect(sync.ahead == 0 && sync.behind == 0)

    try fixture.commit("Local only", files: ["a.txt": "2\n"])
    sync = await repository.syncStatus()
    #expect(sync.ahead == 1)
    #expect(sync.behind == 0)
  }
}

@Suite struct BranchDiffTests {
  @Test func coversCommitsAndUncommittedWorkSinceTheSplit() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["shared.txt": "base\n"])
    let repository = try await GitRepository.open(at: fixture.url)
    let mainName = try #require(await repository.info().branch)
    // On the base branch itself there's nothing to compare with.
    #expect(await repository.branchBase() == nil)

    let git = SystemGit(directory: fixture.url)
    _ = try await git.run(["switch", "-q", "-c", "feature"])
    try fixture.commit("Feature work", files: ["feature.txt": "new\n"])
    try fixture.write("shared.txt", "base\nedited, not committed\n")

    let (diff, comparison) = try await repository.branchDiff()
    #expect(comparison.base == mainName)
    #expect(comparison.branch == "feature")
    #expect(comparison.ahead == 1)
    #expect(diff.source == .branch)
    #expect(Set(diff.files.map(\.path)) == ["feature.txt", "shared.txt"])
  }
}

@Suite struct HistogramDiffTests {
  /// Diffs stay correct with the histogram flag on: a function inserted
  /// between two others shows as pure additions. (Myers often gets this one
  /// right too; this guards the patched flag, not the algorithm's quality.)
  @Test func insertedFunctionShowsAsPureAdditions() async throws {
    let fixture = try FixtureRepository()
    let before = """
      func a() {
        one()
      }

      func c() {
        three()
      }

      """
    let after = """
      func a() {
        one()
      }

      func b() {
        two()
      }

      func c() {
        three()
      }

      """
    try fixture.commit("Base", files: ["f.swift": before])
    try fixture.write("f.swift", after)
    let diff = try await GitRepository.open(at: fixture.url).workingTreeDiff(staged: false, path: "f.swift")
    let lines = diff.files.flatMap(\.hunks).flatMap(\.lines)
    #expect(lines.filter { $0.kind == .deletion }.isEmpty)
    #expect(lines.filter { $0.kind == .addition }.count == 4)
  }
}

@Suite struct CommitSizeTests {
  @Test func measuresStagedOrTrackedChanges() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n2\n", "b.txt": "b\n"])
    try fixture.write("a.txt", "1\ntwo\nthree\n")
    try fixture.stage("a.txt")
    try fixture.write("b.txt", "b\nmore\n")
    try fixture.write("new.txt", "untracked\n")
    let repository = try await GitRepository.open(at: fixture.url)

    #expect(try await repository.commitSize(trackedOnly: false) == ChangeSize(files: 1, additions: 2, deletions: 1))
    // Tracked only: b.txt's unstaged edit; a.txt matches the index; new.txt
    // isn't tracked.
    #expect(try await repository.commitSize(trackedOnly: true) == ChangeSize(files: 1, additions: 1, deletions: 0))
  }
}

@Suite struct PartialStatusTests {
  @Test func checksOnlyTheGivenPathsAndMergesIn() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("Base", files: ["a.txt": "1\n", "b.txt": "1\n", "c.txt": "1\n"])
    try fixture.write("a.txt", "2\n")
    let repository = try await GitRepository.open(at: fixture.url)
    let full = try await repository.status()
    #expect(full.unstaged.map(\.path) == ["a.txt"])

    // b changes and a is put back; a partial status of just b misses a...
    try fixture.write("b.txt", "2\n")
    try fixture.write("a.txt", "1\n")
    let partial = try await repository.status(paths: ["b.txt"])
    #expect(partial.unstaged.map(\.path) == ["b.txt"])
    // ...so merging only replaces what it checked.
    #expect(full.merging(partial, for: ["b.txt"]).unstaged.map(\.path) == ["a.txt", "b.txt"])
    let both = try await repository.status(paths: ["a.txt", "b.txt"])
    #expect(full.merging(both, for: ["a.txt", "b.txt"]).unstaged.map(\.path) == ["b.txt"])

    // A new file in a new folder, and a deletion.
    try fixture.write("new/x.txt", "x\n")
    try fixture.delete("c.txt")
    let more = try await repository.status(paths: ["new/x.txt", "c.txt"])
    #expect(Set(more.unstaged) == [ChangedFile(path: "new/x.txt", kind: .untracked), ChangedFile(path: "c.txt", kind: .deleted)])
  }
}
