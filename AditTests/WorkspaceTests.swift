import Foundation
import Testing

@testable import Adit

@Suite struct RepositoryDiscoveryTests {
  private func makeFolder(_ layout: [String]) throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("adit-ws-\(UUID().uuidString)")
    for path in layout {
      let url = root.appendingPathComponent(path)
      if path.hasSuffix("/.git") && path.contains("worktree") {
        // A linked worktree has a .git file, not a folder.
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("gitdir: /elsewhere\n".utf8).write(to: url)
      } else {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      }
    }
    return root
  }

  @Test func findsSiblingRepositoriesLikePapercheck() throws {
    let root = try makeFolder([
      "frontend/.git", "frontend/src", "backend/.git", "documents/.git", "docs/notes",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let found = RepositoryDiscovery.repositories(in: root)
    #expect(found.map(\.relativePath) == ["backend", "documents", "frontend"])
  }

  @Test func findsNestedOnesAndWorktreesButNotInsideRepositories() throws {
    let root = try makeFolder([
      "apps/web/.git",
      "apps/web/packages/inner/.git",
      "services/api/worktree/.git",
      "node_modules/pkg/.git",
      ".hidden/repo/.git",
      "a/b/c/d/.git",
    ])
    defer { try? FileManager.default.removeItem(at: root) }
    let found = RepositoryDiscovery.repositories(in: root)
    // web is found but not searched inside; dependency and hidden folders are
    // skipped; four levels down is past the limit.
    #expect(found.map(\.relativePath) == ["apps/web", "services/api/worktree"])
  }

  @Test func emptyFolderHasNone() throws {
    let root = try makeFolder(["just/files"])
    defer { try? FileManager.default.removeItem(at: root) }
    #expect(RepositoryDiscovery.repositories(in: root).isEmpty)
  }
}
