import Testing

@testable import Adit

@Suite struct FileOrderTests {
  @Test func sourceThenItsTestsThenConfigThenBulk() {
    let paths = [
      "package-lock.json", "README.md", "AditTests/GitRepositoryTests.swift", "Adit/Git/GitRepository.swift",
      "Adit/Views/DiffPane.swift", "AditTests/UnrelatedTests.swift", "Package.swift",
      "Packages/Clibgit2/libgit2/src/diff.c", "Adit/Models/Latest.swift",
    ]
    #expect(
      FileOrder.smartOrder(paths) == [
        "Adit/Git/GitRepository.swift", "AditTests/GitRepositoryTests.swift",
        "Adit/Models/Latest.swift", "Adit/Views/DiffPane.swift",
        "AditTests/UnrelatedTests.swift",
        "Package.swift", "README.md",
        "Packages/Clibgit2/libgit2/src/diff.c", "package-lock.json",
      ])
  }

  @Test func recognisesTestNames() {
    #expect(FileOrder.testSubject(of: "FooTests.swift") == "foo")
    #expect(FileOrder.testSubject(of: "src/foo.test.ts") == "foo")
    #expect(FileOrder.testSubject(of: "foo_test.go") == "foo")
    #expect(FileOrder.testSubject(of: "test_foo.py") == "foo")
    #expect(FileOrder.testSubject(of: "latest.swift") == nil)
    #expect(FileOrder.testSubject(of: "Contest.swift") == nil)
  }

  @Test func pathOrderIsPlainSort() {
    #expect(FileOrder.path.sorted(["b", "a", "c"], path: { $0 }) == ["a", "b", "c"])
  }
}
