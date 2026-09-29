import Foundation
import Testing

@testable import Glint

/// Zed's rule (project_diff_path_key): a file's place in the Changes list
/// and in Uncommitted Changes depends only on its own status and path, the
/// same for both, so they never disagree and staging never moves a file.
@Suite struct ChangeOrderTests {
  private let status = WorkingTreeStatus(
    staged: [
      ChangedFile(path: "src/new-staged.ts", kind: .added),
      ChangedFile(path: "src/b.ts", kind: .modified),
    ],
    unstaged: [
      ChangedFile(path: "src/a.ts", kind: .modified),
      ChangedFile(path: "zz/untracked.ts", kind: .untracked),
      ChangedFile(path: "merge.ts", kind: .conflicted),
      ChangedFile(path: "src/b.ts", kind: .modified),
    ])

  @Test func conflictsThenTrackedThenUntracked() {
    let paths = status.entries(order: .path, grouping: .trackedUntracked).map(\.path)
    #expect(paths == ["merge.ts", "src/a.ts", "src/b.ts", "src/new-staged.ts", "zz/untracked.ts"])
  }

  @Test func aStagedNewFileIsUntrackedLikeZed() {
    let entry = status.entries.first { $0.path == "src/new-staged.ts" }
    #expect(entry?.section == .untracked)
    #expect(entry?.state == .all)
  }

  @Test func stagingAFileKeepsItsPlace() {
    let before = status.entries(order: .path, grouping: .trackedUntracked).map(\.path)
    for path in before {
      var staged = status
      staged.markStaged(path)
      #expect(staged.entries(order: .path, grouping: .trackedUntracked).map(\.path) == before)
    }
  }
}

/// Uncommitted Changes against real repositories: its files come in the
/// list's order, and staging a file leaves it where it was.
@Suite struct UncommittedOrderTests {
  private func write(_ fixture: FixtureRepository, _ path: String, _ text: String) throws {
    let url = fixture.url.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  @Test func diffOrderIsTheListOrderAndStagingDoesNotMoveFiles() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit(
      "base",
      files: ["notifications/services/emails.py": "a\n", "common/brands/x.json": "{}\n", "tests/test_x.py": "t\n"])
    try write(fixture, "notifications/services/emails.py", "b\n")
    try write(fixture, "common/brands/x.json", "{\"a\": 1}\n")
    try write(fixture, "tests/test_x.py", "u\n")
    try write(fixture, "new/untracked.py", "n\n")
    let repository = try await GitRepository.open(at: fixture.url)

    let first = try await RepositorySession.uncommittedDiff(repository)
    let listOrder = try await repository.status().entries.map(\.path)
    #expect(first.files.map(\.path) == listOrder)
    #expect(first.files.map(\.id) == Array(first.files.indices))

    for path in listOrder {
      try await repository.stage([path])
      let after = try await RepositorySession.uncommittedDiff(repository)
      #expect(after.files.map(\.path) == listOrder, "staging \(path) moved files")
      #expect(after.files.first { $0.path == path }?.isStaged == true)
    }
  }
}

/// The session in Style Zed: the selection follows the list's order, stays
/// on a file you stage by clicking, and Space stages then moves on.
@MainActor @Suite(.serialized) struct ZedSelectionTests {
  private func session() async throws -> (RepositorySession, FixtureRepository) {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["a.py": "1\n", "b.py": "1\n", "c.py": "1\n"])
    for path in ["a.py", "b.py", "c.py"] {
      try "2\n".write(to: fixture.url.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    await settle(session)
    return (session, fixture)
  }

  private func settle(_ session: RepositorySession) async {
    for _ in 0..<100 {
      await session.indexWrites?.value
      await session.statusTask?.value
      await session.diffTask?.value
      if session.pendingIndexWrites == 0 && session.statusTask == nil { break }
      try? await Task.sleep(for: .milliseconds(10))
    }
    try? await Task.sleep(for: .milliseconds(50))
  }

  private func withZed(_ body: () async throws -> Void) async rethrows {
    let was = Theme.shared.usesLiquidGlass
    Theme.shared.setUsesLiquidGlassForTesting(false)
    defer { Theme.shared.setUsesLiquidGlassForTesting(was) }
    try await body()
  }

  @Test func clickingAFilesBoxKeepsTheSelectionWhereItIs() async throws {
    try await withZed {
      let (session, _) = try await session()
      session.selectedChange = ChangeSelection(staged: false, path: "b.py")
      session.setStaged("b.py", true)
      await settle(session)
      #expect(session.selectedChange?.path == "b.py")
      session.setStaged("a.py", true)
      await settle(session)
      #expect(session.selectedChange?.path == "b.py")
    }
  }

  @Test func spaceStagesThenMovesToTheNextFileInListOrder() async throws {
    try await withZed {
      let (session, _) = try await session()
      session.tab = .changes
      let order = session.status.entries.map(\.path)
      session.selectedChange = ChangeSelection(staged: false, path: order[0])
      session.toggleSelectedStaged()
      await settle(session)
      #expect(session.status.entries.first { $0.path == order[0] }?.state == .all)
      #expect(session.selectedChange?.path == order[1])
      // Back on a staged file, Space unstages it.
      session.selectedChange = ChangeSelection(staged: false, path: order[0])
      session.toggleSelectedStaged()
      await settle(session)
      #expect(session.status.entries.first { $0.path == order[0] }?.state == StageState.none)
    }
  }

  @Test func nextAndPreviousFollowTheListOrder() async throws {
    try await withZed {
      let (session, _) = try await session()
      session.tab = .changes
      let order = session.status.entries.map(\.path)
      session.selectedChange = ChangeSelection(staged: false, path: order[0])
      session.selectNextItem()
      #expect(session.selectedChange?.path == order[1])
      session.selectNextItem()
      #expect(session.selectedChange?.path == order[2])
      session.selectPreviousItem()
      #expect(session.selectedChange?.path == order[1])
    }
  }
}
