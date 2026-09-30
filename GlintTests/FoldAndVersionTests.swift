import Foundation
import Testing

@testable import Glint

/// Style Zed's Uncommitted Changes folds a file once it's fully staged,
/// unless you open it again.
@MainActor @Suite(.serialized) struct StagedFoldTests {
  private func settle(_ session: RepositorySession) async {
    for _ in 0..<100 {
      await session.indexWrites?.value
      await session.statusTask?.value
      await session.diffTask?.value
      if session.pendingIndexWrites == 0 && session.statusTask == nil { break }
      try? await Task.sleep(for: .milliseconds(10))
    }
    await session.diffTask?.value
    try? await Task.sleep(for: .milliseconds(50))
    await session.diffTask?.value
  }

  private func index(_ session: RepositorySession, _ path: String) -> Int? {
    session.diff?.files.first { $0.path == path }?.id
  }

  @Test func stagedFilesFoldUnlessYouOpenThem() async throws {
    let was = Theme.shared.usesLiquidGlass
    Theme.shared.setUsesLiquidGlassForTesting(false)
    defer { Theme.shared.setUsesLiquidGlassForTesting(was) }

    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["a.py": "1\n", "b.py": "1\n"])
    for path in ["a.py", "b.py"] {
      try "2\n".write(to: fixture.url.appendingPathComponent(path), atomically: true, encoding: .utf8)
    }
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    session.tab = .changes
    session.selectedChange = ChangeSelection(staged: false, path: "b.py")
    await settle(session)
    #expect(session.collapsedFiles.isEmpty)

    // Staged: folded.
    session.setStaged("a.py", true)
    await settle(session)
    let a = try #require(index(session, "a.py"))
    #expect(session.collapsedFiles == [a])

    // Opened by hand: stays open through reloads.
    session.toggleCollapsed(a)
    session.refreshWorkingTree()
    await settle(session)
    #expect(!session.collapsedFiles.contains(a))

    // Unstaged and staged again: folds again.
    session.setStaged("a.py", false)
    await settle(session)
    #expect(session.collapsedFiles.isEmpty)
    session.setStaged("a.py", true)
    await settle(session)
    #expect(session.collapsedFiles == [try #require(index(session, "a.py"))])

    // A file you fold stays folded, staged or not.
    let b = try #require(index(session, "b.py"))
    session.toggleCollapsed(b)
    session.refreshWorkingTree()
    await settle(session)
    #expect(session.collapsedFiles.contains(b))
  }
}

extension StagedFoldTests {
  /// The first diff at launch comes a different way; it folds too.
  @Test func aFileStagedBeforeOpeningIsFoldedAtLaunch() async throws {
    let was = Theme.shared.usesLiquidGlass
    Theme.shared.setUsesLiquidGlassForTesting(false)
    defer { Theme.shared.setUsesLiquidGlassForTesting(was) }

    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["a.py": "1\n", "b.py": "1\n"])
    try fixture.write("a.py", "2\n")
    try fixture.stage("a.py")
    try fixture.write("b.py", "2\n")
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    await settle(session)
    #expect(session.diff?.files.map(\.path) == ["a.py", "b.py"])
    #expect(session.collapsedFiles == [try #require(index(session, "a.py"))])
  }
}

@Suite struct VersionHistoryTests {
  @Test func parsesVersionsNewestFirst() {
    let versions = VersionHistory.parse("# 0.2.0\n\n- One\n- Two `code`\n\n# 0.1.0\n- First\n")
    #expect(versions.map(\.number) == ["0.2.0", "0.1.0"])
    #expect(versions[0].changes == ["One", "Two `code`"])
  }

  @Test func theBundledChangelogCoversTheRunningVersion() {
    let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    #expect(VersionHistory.bundled.first?.number == current)
  }
}

@MainActor @Suite struct DiagnosticsTests {
  @Test func alertsAreLoggedAndTheReportHasTheVersion() {
    _ = UserAlert("Couldn't push", message: "diagnostics-test-marker")
    let report = Diagnostics.report(since: Date().addingTimeInterval(-60))
    #expect(report.hasPrefix("Glint \(Diagnostics.version)"))
    #expect(report.contains("## Crash and hang reports"))
  }
}
