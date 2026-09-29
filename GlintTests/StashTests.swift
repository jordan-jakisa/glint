import Foundation
import Testing

@testable import Glint

@Suite struct StashTests {
  @Test func parsesNamedUnnamedDetachedAndOtherSubjects() {
    let list = [
      "stash@{0}\u{1F}\(String(repeating: "a", count: 40))\u{1F}1790600801\u{1F}On main: half-done login",
      "stash@{1}\u{1F}\(String(repeating: "b", count: 40))\u{1F}1790600000\u{1F}WIP on feature/x: bd15314 Fix the build: again",
      "stash@{2}\u{1F}\(String(repeating: "c", count: 40))\u{1F}1790500000\u{1F}WIP on (no branch): 1a2b3c4 Detached work",
      "stash@{3}\u{1F}\(String(repeating: "d", count: 40))\u{1F}1790400000\u{1F}autostash",
      "not a stash line",
    ].joined(separator: "\n") + "\n"

    let stashes = Stash.parse(list: list)
    #expect(stashes.map(\.index) == [0, 1, 2, 3])
    #expect(stashes.map(\.branch) == ["main", "feature/x", nil, nil])
    #expect(stashes.map(\.message) == ["half-done login", "Fix the build: again", "Detached work", "autostash"])
    #expect(stashes.map(\.isNamed) == [true, false, false, true])
    #expect(stashes[1].title == "WIP: Fix the build: again")
    #expect(stashes[0].title == "half-done login")
    #expect(stashes[2].reference == "stash@{2}")
    #expect(stashes[0].date == Date(timeIntervalSince1970: 1_790_600_801))
  }

  @Test func pushArgumentsPerKind() {
    #expect(StashKind.all.pushArguments(named: "") == ["stash", "push", "--include-untracked"])
    #expect(StashKind.tracked.pushArguments(named: "  ") == ["stash", "push"])
    #expect(
      StashKind.staged.pushArguments(named: " wip login ") == ["stash", "push", "--staged", "--message", "wip login"])
  }

  @Test func pushApplyPopAndDropARealStash() async throws {
    let fixture = try FixtureRepository()
    _ = try fixture.commit("Base", files: ["a.txt": "a\n"])
    let git = SystemGit(directory: fixture.url)
    _ = try await git.run(["config", "user.name", "Test Author"])
    _ = try await git.run(["config", "user.email", "test@example.com"])
    func list() async throws -> [Stash] {
      Stash.parse(list: try await git.run(["stash", "list", "--format=\(Stash.listFormat)"]))
    }
    func contents(_ path: String) -> String? {
      try? String(contentsOf: fixture.url.appendingPathComponent(path), encoding: .utf8)
    }

    // Nothing to stash: git says so and exits 0.
    let empty = try await git.run(StashKind.all.pushArguments(named: ""))
    #expect(empty.contains("No local changes to save"))
    #expect(try await list().isEmpty)

    // Stash all takes the untracked file too.
    try fixture.write("a.txt", "changed\n")
    try fixture.write("new.txt", "new\n")
    _ = try await git.run(StashKind.all.pushArguments(named: "login work"))
    #expect(contents("a.txt") == "a\n")
    #expect(contents("new.txt") == nil)

    // Stash tracked leaves the untracked file behind.
    try fixture.write("a.txt", "second\n")
    try fixture.write("left.txt", "stays\n")
    _ = try await git.run(StashKind.tracked.pushArguments(named: ""))
    #expect(contents("a.txt") == "a\n")
    #expect(contents("left.txt") == "stays\n")
    try fixture.delete("left.txt")

    var stashes = try await list()
    #expect(stashes.map(\.index) == [0, 1])
    #expect(stashes[0].isNamed == false)
    #expect(stashes[0].message == "Base")
    #expect(stashes[1].message == "login work")
    #expect(stashes[1].isNamed)

    // Its diff, untracked file included, for the preview.
    let patch = try await git.run(["stash", "show", "--patch", "--no-color", "--include-untracked", stashes[1].id])
    #expect(patch.contains("+changed"))
    #expect(patch.contains("+++ b/new.txt"))

    // Apply keeps it; pop removes it.
    _ = try await git.run(["stash", "apply", stashes[1].reference])
    #expect(contents("a.txt") == "changed\n")
    #expect(contents("new.txt") == "new\n")
    #expect(try await list().count == 2)
    _ = try await git.run(["reset", "--hard"])
    try fixture.delete("new.txt")

    _ = try await git.run(["stash", "pop", "stash@{0}"])
    #expect(contents("a.txt") == "second\n")
    stashes = try await list()
    #expect(stashes.map(\.message) == ["login work"])
    #expect(stashes[0].index == 0)
    _ = try await git.run(["reset", "--hard"])

    // Drop by the reference the list gives now.
    _ = try await git.run(["stash", "drop", stashes[0].reference])
    #expect(try await list().isEmpty)
  }

  @Test func stashStagedLeavesUnstagedChanges() async throws {
    let fixture = try FixtureRepository()
    _ = try fixture.commit("Base", files: ["a.txt": "a\n", "b.txt": "b\n"])
    let git = SystemGit(directory: fixture.url)
    _ = try await git.run(["config", "user.name", "Test Author"])
    _ = try await git.run(["config", "user.email", "test@example.com"])
    try fixture.write("a.txt", "staged\n")
    try fixture.stage("a.txt")
    try fixture.write("b.txt", "unstaged\n")

    _ = try await git.run(StashKind.staged.pushArguments(named: "just staged"))
    let a = try String(contentsOf: fixture.url.appendingPathComponent("a.txt"), encoding: .utf8)
    let b = try String(contentsOf: fixture.url.appendingPathComponent("b.txt"), encoding: .utf8)
    #expect(a == "a\n")
    #expect(b == "unstaged\n")
  }

  @Test @MainActor func stashFailuresGetPlainAdvice() {
    #expect(UserAlert.advice(forGit: "No stash entries found.") == "You don't have any stashes.")
    #expect(UserAlert.advice(forGit: "error: unknown option `staged'\nusage: git stash").contains("2.35"))
    #expect(
      UserAlert.advice(forGit: "u already exists, no checkout\nerror: could not restore untracked files from stash")
        .hasPrefix("New files in the stash"))
    #expect(
      UserAlert.advice(forGit: "CONFLICT (content): Merge conflict in a\nThe stash entry is kept in case you need it again.")
        .contains("still in the list"))
  }
}
