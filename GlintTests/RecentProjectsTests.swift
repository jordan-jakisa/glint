import Foundation
import Testing

@testable import Glint

@MainActor
@Suite struct RecentProjectsTests {
  private let defaults: UserDefaults
  private let root: URL

  init() throws {
    let suite = "RecentProjectsTests.\(UUID().uuidString)"
    defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    root = FileManager.default.temporaryDirectory.appending(path: "recents-\(UUID().uuidString)")
    for name in ["a", "b", "c"] {
      try FileManager.default.createDirectory(at: root.appending(path: name), withIntermediateDirectories: true)
    }
  }

  private func folder(_ name: String) -> URL { root.appending(path: name) }

  private func names(_ access: RepositoryAccess) -> [String] { access.recents().map(\.lastPathComponent) }

  @Test func newestFirstWithoutDuplicates() {
    let access = RepositoryAccess(defaults: defaults)
    access.adopt(folder("a"))
    access.adopt(folder("b"))
    access.adopt(folder("a"))
    #expect(names(access) == ["a", "b"])
    #expect(access.restore()?.lastPathComponent == "a")
  }

  @Test func forgetsOneThatFailedAndOnesThatAreGone() throws {
    let access = RepositoryAccess(defaults: defaults)
    for name in ["a", "b", "c"] { access.adopt(folder(name)) }
    access.forget(folder("b"))
    #expect(names(access) == ["c", "a"])
    try FileManager.default.removeItem(at: folder("c"))
    #expect(names(access) == ["a"])
  }

  @Test func keepsTheLastTen() throws {
    let access = RepositoryAccess(defaults: defaults)
    for index in 0..<12 {
      let url = folder("p\(index)")
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      access.adopt(url)
    }
    #expect(names(access) == (2..<12).reversed().map { "p\($0)" })
  }

  @Test func bringsOverTheRepositoryFromBefore() throws {
    let legacy = try folder("b").bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    defaults.set(legacy, forKey: "lastRepositoryBookmark")
    let access = RepositoryAccess(defaults: defaults)
    #expect(names(access) == ["b"])
    #expect(defaults.data(forKey: "lastRepositoryBookmark") == nil)
  }
}
