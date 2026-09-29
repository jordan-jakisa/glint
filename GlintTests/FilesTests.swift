import Foundation
import Testing

@testable import Glint

@Suite struct FileTreeTests {
  private let files = ["README.md", "src/app/page.tsx", "src/lib/a.ts", "src/lib/b.ts", ".env"]

  @Test func foldersFirstThenFilesCollapsedByDefault() {
    let rows = FileTree.rows(files: files, folders: [], expanded: [], query: "")
    #expect(rows.map(\.name) == ["src", ".env", "README.md"])
    #expect(rows.first?.isFolder == true)
  }

  @Test func expandingShowsChildrenIndented() {
    let rows = FileTree.rows(files: files, folders: [], expanded: ["src", "src/lib"], query: "")
    #expect(rows.map(\.path) == ["src", "src/app", "src/lib", "src/lib/a.ts", "src/lib/b.ts", ".env", "README.md"])
    #expect(rows.first { $0.path == "src/lib/a.ts" }?.depth == 2)
  }

  @Test func ignoredFoldersShowWithNothingInsideYet() {
    let rows = FileTree.rows(files: ["a.ts"], folders: ["node_modules"], expanded: [], query: "")
    #expect(rows.map(\.path) == ["node_modules", "a.ts"])
    #expect(rows.first?.isFolder == true)
  }

  @Test func filterIsFlatByPath() {
    let rows = FileTree.rows(files: files, folders: [], expanded: [], query: "lib")
    #expect(rows.map(\.path) == ["src/lib/a.ts", "src/lib/b.ts"])
    #expect(rows.allSatisfy { !$0.isFolder && $0.depth == 0 })
  }

  @Test func rowIDsAreUnique() {
    let rows = FileTree.rows(files: files + ["src"], folders: ["src"], expanded: ["src"], query: "")
    #expect(Set(rows.map(\.id)).count == rows.count)
  }
}

/// The Files tab against real repositories: what's listed, including
/// ignored files, and across a folder of repositories.
@MainActor @Suite struct ProjectFilesTests {
  private func settle(_ session: RepositorySession, until condition: () -> Bool) async {
    for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(10)) }
  }

  @Test func listsTrackedUntrackedAndIgnored() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: [".gitignore": ".env\nnode_modules/\n", "src/a.ts": "a\n"])
    for (path, text) in [".env": "SECRET=1\n", "node_modules/x/index.js": "x\n", "new.ts": "n\n"] {
      let url = fixture.url.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try text.write(to: url, atomically: true, encoding: .utf8)
    }
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    session.loadProjectFiles()
    await settle(session) { session.projectFiles.contains(".env") }
    #expect(session.projectFiles.contains("src/a.ts"))
    #expect(session.projectFiles.contains("new.ts"))
    #expect(session.projectFiles.contains(".env"))
    #expect(session.ignoredFiles.contains(".env"))
    #expect(session.ignoredFolders == ["node_modules"])
    // Never walked into.
    #expect(!session.projectFiles.contains { $0.hasPrefix("node_modules/") })
  }

  @Test func showFileOpensItAndSwitchingSavesTheLastOne() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["a.ts": "a\n", "b.ts": "b\n"])
    let session = RepositorySession()
    session.install(try await RepositorySession.load(fixture.url))
    session.showFile("a.ts")
    #expect(session.tab == .files)
    #expect(session.openedFile?.text == "a")
    session.openedFile?.text = "A"
    session.showFile("b.ts")
    #expect(try String(contentsOf: fixture.url.appendingPathComponent("a.ts"), encoding: .utf8) == "A\n")
    #expect(session.openedFilePath == "b.ts")
    session.closeOpenedFile()
  }

  @Test func aFolderOfRepositoriesListsEachAsAFolder() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("glint-files-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    for name in ["api", "web"] {
      _ = try await SystemGit(directory: root).run(["init", "-q", "-b", "main", name])
      try "x\n".write(to: root.appendingPathComponent("\(name)/main.ts"), atomically: true, encoding: .utf8)
    }
    try "notes\n".write(to: root.appendingPathComponent("NOTES.md"), atomically: true, encoding: .utf8)
    let session = RepositorySession()
    session.install(try await RepositorySession.load(root))
    await session.summaryTask?.value
    session.loadProjectFiles()
    await settle(session) { session.projectFiles.count >= 3 }
    #expect(Set(session.projectFiles) == ["api/main.ts", "web/main.ts", "NOTES.md"])
    #expect(session.filesRoot?.standardizedFileURL == root.standardizedFileURL)
  }
}
