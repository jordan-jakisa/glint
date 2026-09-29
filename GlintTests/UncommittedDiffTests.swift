import Foundation
import Testing

@testable import Glint

@Suite struct UncommittedDiffTests {
  /// Style Zed's Uncommitted Changes: unstaged files, then fully staged ones
  /// marked as staged, and a partly staged file only once.
  /// Every file once, in the list's order, a fully staged one in its own
  /// place (not moved to the end), as in Zed's Uncommitted Changes.
  @Test func listsEveryFileInTheListsOrder() async throws {
    let fixture = try FixtureRepository()
    _ = try fixture.commit("Base", files: ["a.txt": "a\n", "b.txt": "b\n", "c.txt": "c\n"])
    try fixture.write("a.txt", "a changed\n")
    try fixture.write("b.txt", "b staged\n")
    try fixture.stage("b.txt")
    try fixture.write("c.txt", "c staged\n")
    try fixture.stage("c.txt")
    try fixture.write("c.txt", "c staged\nand more\n")
    let repository = try await GitRepository.open(at: fixture.url)

    let diff = try await RepositorySession.uncommittedDiff(repository)
    #expect(diff.files.map(\.path) == ["a.txt", "b.txt", "c.txt"])
    #expect(diff.files.map(\.isStaged) == [false, true, false])
    #expect(diff.files.map(\.id) == [0, 1, 2])
  }
}
