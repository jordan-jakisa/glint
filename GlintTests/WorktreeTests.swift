import Foundation
import Testing

@testable import Glint

@Suite struct WorktreeTests {
  @Test func parsesPorcelainMainFirstAndSkipsBare() {
    let porcelain = """
      worktree /work/app
      HEAD 1111111111111111111111111111111111111111
      branch refs/heads/main

      worktree /work/app-feature-login
      HEAD 2222222222222222222222222222222222222222
      branch refs/heads/feature/login

      worktree /work/app-detached
      HEAD 3333333333333333333333333333333333333333
      detached

      worktree /work/bare.git
      bare

      """
    let worktrees = Worktree.parse(porcelain: porcelain)
    #expect(worktrees.map(\.url.path) == ["/work/app", "/work/app-feature-login", "/work/app-detached"])
    #expect(worktrees.map(\.branch) == ["main", "feature/login", nil])
    #expect(worktrees.map(\.isMain) == [true, false, false])
    #expect(worktrees[1].name == "app-feature-login")
  }

  @Test func readsARealLinkedWorktree() async throws {
    let fixture = try FixtureRepository()
    _ = try fixture.commit("Base", files: ["a.txt": "a\n"])
    let linked = fixture.url.deletingLastPathComponent()
      .appendingPathComponent(fixture.url.lastPathComponent + "-topic")
    defer { try? FileManager.default.removeItem(at: linked) }
    let git = SystemGit(directory: fixture.url)
    _ = try await git.run(["worktree", "add", "-b", "topic", linked.path])

    let worktrees = Worktree.parse(porcelain: try await git.run(["worktree", "list", "--porcelain"]))
    #expect(worktrees.count == 2)
    #expect(worktrees[0].isMain)
    #expect(worktrees[1].branch == "topic")
    #expect(worktrees[1].url.resolvingSymlinksInPath().path == linked.resolvingSymlinksInPath().path)
  }
}
