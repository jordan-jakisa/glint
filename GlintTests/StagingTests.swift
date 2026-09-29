import Foundation
import Testing

@testable import Glint

/// Staging, end to end at the git layer and in the Changes list's model:
/// what's ticked must be what git has staged.
@Suite struct StagingRegressionTests {
  private func write(_ fixture: FixtureRepository, _ path: String, _ text: String) throws {
    let url = fixture.url.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  private func fixture() throws -> FixtureRepository {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["messages/de.json": "{}\n", "messages/en.json": "{}\n", "src/routes.ts": "a\n"])
    return fixture
  }

  @Test func newFilesStagedAreAddedAndNotUntracked() async throws {
    let fixture = try fixture()
    try write(fixture, "src/lib/gdpr-consent.ts", "export {}\n")
    try write(fixture, "src/app/_components/consent-banner.tsx", "export {}\n")
    let repository = try await GitRepository.open(at: fixture.url)
    try await repository.stage(["src/lib/gdpr-consent.ts", "src/app/_components/consent-banner.tsx"])
    let status = try await repository.status()
    #expect(Set(status.staged.map(\.path)) == ["src/lib/gdpr-consent.ts", "src/app/_components/consent-banner.tsx"])
    #expect(status.staged.allSatisfy { $0.kind == .added })
    #expect(status.unstaged.isEmpty)
    #expect(status.entries.allSatisfy { $0.state == .all })
  }

  @Test func checkingJustTheChangedPathsKeepsStagedNewFiles() async throws {
    let fixture = try fixture()
    try write(fixture, "src/lib/gdpr-consent.ts", "export {}\n")
    try write(fixture, "messages/en.json", "{\"a\": 1}\n")
    let repository = try await GitRepository.open(at: fixture.url)
    let before = try await repository.status()
    try await repository.stage(["src/lib/gdpr-consent.ts", "messages/en.json"])
    let paths: Set<String> = ["src/lib/gdpr-consent.ts", "messages/en.json"]
    let partial = try await repository.status(paths: Array(paths))
    let merged = before.merging(partial, for: paths)
    #expect(merged == (try await repository.status()))
    #expect(merged.entries.first { $0.path == "src/lib/gdpr-consent.ts" }?.state == .all)
  }

  @Test func quickClicksOnSeveralFilesAllLand() async throws {
    let fixture = try fixture()
    let paths = ["messages/de.json", "messages/en.json", "src/routes.ts", "src/lib/a.ts", "src/lib/b.ts"]
    for path in paths { try write(fixture, path, "changed \(path)\n") }
    let repository = try await GitRepository.open(at: fixture.url)
    // As fast as clicks can come: every write overlapping the others.
    await withTaskGroup(of: Void.self) { group in
      for path in paths { group.addTask { try? await repository.stage([path]) } }
    }
    let staged = try await repository.status()
    #expect(Set(staged.staged.map(\.path)) == Set(paths))
    #expect(staged.unstaged.isEmpty)

    await withTaskGroup(of: Void.self) { group in
      for path in paths.prefix(3) { group.addTask { try? await repository.unstage([path]) } }
    }
    let status = try await repository.status()
    #expect(Set(status.unstaged.map(\.path)) == Set(paths.prefix(3)))
    #expect(Set(status.staged.map(\.path)) == Set(paths.suffix(2)))
  }

  @Test func unstagingANewFileMakesItUntracked() async throws {
    let fixture = try fixture()
    try write(fixture, "new.ts", "x\n")
    let repository = try await GitRepository.open(at: fixture.url)
    try await repository.stage(["new.ts"])
    try await repository.unstage(["new.ts"])
    let status = try await repository.status()
    #expect(status.staged.isEmpty)
    #expect(status.unstaged == [ChangedFile(path: "new.ts", kind: .untracked)])
    #expect(status.entries.first?.state == StageState.none)
  }

  @Test func partlyStagedIsPartial() async throws {
    let fixture = try fixture()
    try write(fixture, "src/routes.ts", "b\n")
    let repository = try await GitRepository.open(at: fixture.url)
    try await repository.stage(["src/routes.ts"])
    try write(fixture, "src/routes.ts", "c\n")
    let status = try await repository.status()
    #expect(status.entries.first { $0.path == "src/routes.ts" }?.state == .partial)
  }
}

/// The list's model: one entry per path, ticked by what git has staged.
@Suite struct StagingEntryTests {
  private let order = FileOrder.path

  @Test func statesFollowTheGroups() {
    let status = WorkingTreeStatus(
      staged: [
        ChangedFile(path: "added.ts", kind: .added), ChangedFile(path: "both.ts", kind: .modified),
      ],
      unstaged: [
        ChangedFile(path: "both.ts", kind: .modified), ChangedFile(path: "new.ts", kind: .untracked),
        ChangedFile(path: "edited.ts", kind: .modified),
      ])
    let states = Dictionary(uniqueKeysWithValues: status.entries.map { ($0.path, $0.state) })
    #expect(states == ["added.ts": .all, "both.ts": .partial, "new.ts": StageState.none, "edited.ts": StageState.none])
  }

  @Test func listOrderIsTheDiffsFileOrder() {
    let paths = ["notifications/tests/test_marketing.py", "common/brands/uniwunder.json", "notifications/services/emails.py"]
    let status = WorkingTreeStatus(staged: [], unstaged: paths.map { ChangedFile(path: $0, kind: .modified) })
    #expect(status.entries.map(\.path) == FileOrder.current.sorted(paths, path: { $0 }))
    #expect(FileOrder.smart.sorted(paths, path: { $0 }).first == "notifications/services/emails.py")
  }

  @Test func aStagedNewFileIsTrackedAndAdded() {
    let status = WorkingTreeStatus(staged: [ChangedFile(path: "a.ts", kind: .added)], unstaged: [])
    #expect(status.entries.first?.kind == .added)
    #expect(status.entries.first?.state == .all)
  }

  @Test func optimisticStagingMatchesWhatGitWillSay() {
    var status = WorkingTreeStatus(
      staged: [], unstaged: [ChangedFile(path: "new.ts", kind: .untracked), ChangedFile(path: "m.ts", kind: .modified)])
    status.markStaged("new.ts")
    status.markStaged("m.ts")
    #expect(status.entries.allSatisfy { $0.state == .all })
    #expect(status.staged.first { $0.path == "new.ts" }?.kind == .added)
    status.markUnstaged("new.ts")
    #expect(status.unstaged == [ChangedFile(path: "new.ts", kind: .untracked)])
  }

  @Test func stagingAPartlyStagedFileStagesTheRest() {
    var status = WorkingTreeStatus(
      staged: [ChangedFile(path: "a.ts", kind: .modified)], unstaged: [ChangedFile(path: "a.ts", kind: .modified)])
    status.markStaged("a.ts")
    #expect(status.entries.first?.state == .all)
    #expect(status.staged.count == 1)
  }
}

/// The session: quick clicks, with the file watcher refreshing in between,
/// must end with the list ticked exactly as git has it, and never untick
/// something you just ticked.
@MainActor @Suite struct StagingSessionTests {
  private func session(changing paths: [String]) async throws -> (RepositorySession, FixtureRepository) {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["a.ts": "1\n", "b.ts": "1\n", "c.ts": "1\n"])
    for path in paths {
      try "changed \(path)\n".write(to: fixture.url.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    await settle(session)
    return (session, fixture)
  }

  /// Waits for index writes and status reads to finish.
  private func settle(_ session: RepositorySession) async {
    for _ in 0..<50 {
      await session.indexWrites?.value
      await session.statusTask?.value
      if session.pendingIndexWrites == 0 && session.statusTask == nil { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test func quickClicksWithRefreshesInBetweenEndTicked() async throws {
    let paths = ["a.ts", "b.ts", "c.ts", "new1.ts", "new2.ts"]
    let (session, fixture) = try await session(changing: paths)
    #expect(session.status.entries.count == paths.count)
    for path in paths {
      session.setStaged(path, true)
      // The watcher sees .git/index change and asks for a refresh.
      session.refreshWorkingTree()
      #expect(session.status.entries.first { $0.path == path }?.state == .all)
    }
    await settle(session)
    #expect(session.status.entries.allSatisfy { $0.state == .all })
    let repository = try await GitRepository.open(at: fixture.url)
    #expect(session.status == (try await repository.status()))
  }

  @Test func stageThenUnstageQuicklyEndsUnstaged() async throws {
    let (session, fixture) = try await session(changing: ["a.ts", "new.ts"])
    session.setStaged("a.ts", true)
    session.setStaged("new.ts", true)
    session.setStaged("a.ts", false)
    session.refreshWorkingTree()
    session.setStaged("new.ts", false)
    await settle(session)
    #expect(session.status.entries.allSatisfy { $0.state == StageState.none })
    let repository = try await GitRepository.open(at: fixture.url)
    #expect(session.status == (try await repository.status()))
  }

  @Test func stageAllAndUnstageAll() async throws {
    let (session, _) = try await session(changing: ["a.ts", "b.ts", "new.ts"])
    session.stageAll()
    await settle(session)
    #expect(session.status.entries.allSatisfy { $0.state == .all })
    session.unstageAll()
    await settle(session)
    #expect(session.status.entries.allSatisfy { $0.state == StageState.none })
  }
}
