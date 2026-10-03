import Foundation
import Testing

@testable import Glint

/// Zed's own tests for its git panel and project diff (crates/git_ui:
/// `git_panel.rs`, `project_diff.rs`), ported. Each names the Zed test it
/// comes from. Zed builds its fixtures with a fake file system; these use a
/// real repository where git can make the state, and the status model
/// where it can't (conflicts).
@Suite struct ZedPortTests {
  private func modified(_ paths: [String]) -> [ChangedFile] { paths.map { ChangedFile(path: $0, kind: .modified) } }

  private func write(_ fixture: FixtureRepository, _ files: [String: String]) throws {
    for (path, text) in files {
      let url = fixture.url.appendingPathComponent(path)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try text.write(to: url, atomically: true, encoding: .utf8)
    }
  }

  /// project_diff.rs `test_excerpts_are_ordered_by_path`: 20 changed files
  /// come out in path order, each once.
  @Test func excerptsAreOrderedByPath() async throws {
    let fixture = try FixtureRepository()
    let names = (0..<20).map { String(format: "f%02d.txt", $0) }
    try fixture.commit("base", files: Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, "old-\($0)\n") }))
    try write(fixture, Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, "new-\($0)\n") }))
    let repository = try await GitRepository.open(at: fixture.url)
    let diff = RepositorySession.mergeUncommitted(
      unstaged: try await repository.workingTreeDiff(staged: false, path: nil),
      staged: try await repository.workingTreeDiff(staged: true, path: nil),
      status: try await repository.status(), order: .path, grouping: .trackedUntracked, tree: false)
    #expect(diff.files.map(\.path) == names)
  }

  /// project_diff.rs `test_sort_by_name_tie_breaks_on_path`.
  @Test func sortByNameTieBreaksOnPath() {
    let status = WorkingTreeStatus(staged: [], unstaged: modified(["lib/foo.rs", "src/foo.rs", "m.rs"]))
    #expect(ChangeList.diffOrder(status, order: .name, grouping: .none, tree: false) == ["lib/foo.rs", "src/foo.rs", "m.rs"])
  }

  /// project_diff.rs `test_tree_view_orders_directories_before_files`.
  @Test func treeViewOrdersDirectoriesBeforeFiles() {
    let status = WorkingTreeStatus(staged: [], unstaged: modified(["src/a.rs", "src/m.rs", "src/sub/b.rs"]))
    #expect(ChangeList.diffOrder(status, order: .path, grouping: .none, tree: true) == ["src/sub/b.rs", "src/a.rs", "src/m.rs"])
  }

  /// git_panel.rs `test_bulk_staging_with_sort_by_paths`: grouped by status
  /// (Conflicts, Tracked, New), then ungrouped, where conflicts sort in
  /// with everything else.
  @Test func sortByPathsWithAndWithoutGrouping() {
    let status = WorkingTreeStatus(
      staged: [],
      unstaged: modified(["src/main.rs", "src/lib.rs", "tests/test.rs"]) + [
        ChangedFile(path: "new_file.txt", kind: .untracked), ChangedFile(path: "another_new.rs", kind: .untracked),
        ChangedFile(path: "src/utils.rs", kind: .untracked), ChangedFile(path: "conflict.txt", kind: .conflicted),
      ])
    let grouped = ChangeList.sections(status, order: .path, grouping: .trackedUntracked, tree: false)
    #expect(grouped.map(\.title) == ["Conflicts", "Tracked", "Untracked"])
    #expect(grouped.map { $0.entries.map(\.path) } == [
      ["conflict.txt"], ["src/lib.rs", "src/main.rs", "tests/test.rs"], ["another_new.rs", "new_file.txt", "src/utils.rs"],
    ])
    #expect(ChangeList.diffOrder(status, order: .path, grouping: .trackedUntracked, tree: false) == grouped.flatMap { $0.entries.map(\.path) })
    let flat = ChangeList.sections(status, order: .path, grouping: .none, tree: false)
    #expect(flat.count == 1)
    #expect(flat[0].entries.map(\.path) == [
      "another_new.rs", "conflict.txt", "new_file.txt", "src/lib.rs", "src/main.rs", "src/utils.rs", "tests/test.rs",
    ])
  }

  /// git_panel.rs `test_group_by_staging_section_membership_and_order`: a
  /// partly staged file is in both Staged and Unstaged; new files, staged or
  /// not, are the created ones.
  @Test func groupByStagingSectionMembershipAndOrder() {
    let status = WorkingTreeStatus(
      staged: [
        ChangedFile(path: "partial.rs", kind: .modified), ChangedFile(path: "partial_new.rs", kind: .added),
        ChangedFile(path: "staged.rs", kind: .modified),
      ],
      unstaged: [
        ChangedFile(path: "conflict.rs", kind: .conflicted), ChangedFile(path: "new.rs", kind: .untracked),
        ChangedFile(path: "partial.rs", kind: .modified), ChangedFile(path: "partial_new.rs", kind: .modified),
        ChangedFile(path: "unstaged.rs", kind: .modified),
      ])
    let sections = ChangeList.sections(status, order: .path, grouping: .stagedUnstaged, tree: false)
    #expect(sections.map(\.title) == ["Conflicts", "Staged", "Unstaged"])
    #expect(sections.map { $0.entries.map(\.path) } == [
      ["conflict.rs"], ["partial.rs", "partial_new.rs", "staged.rs"], ["new.rs", "partial.rs", "partial_new.rs", "unstaged.rs"],
    ])
    #expect(status.unsortedEntries.filter { $0.section == .untracked }.map(\.path).sorted() == ["new.rs", "partial_new.rs"])
    #expect(status.unsortedEntries.first { $0.path == "partial.rs" }?.state == .partial)
    // Selection walks each file once, in the order shown.
    #expect(ChangeList.visibleOrder(status, order: .path, grouping: .stagedUnstaged, tree: false).map(\.path) == [
      "conflict.rs", "partial.rs", "partial_new.rs", "staged.rs", "new.rs", "unstaged.rs",
    ])
  }

  /// git_panel.rs `test_tree_view_without_status_grouping_combines_statuses`:
  /// no headers, and a folder holds its files whatever their status.
  @Test func treeViewWithoutStatusGroupingCombinesStatuses() {
    let status = WorkingTreeStatus(
      staged: [],
      unstaged: modified(["src/main.rs", "tests/main_test.rs"]) + [ChangedFile(path: "src/utils.rs", kind: .untracked)])
    let sections = ChangeList.sections(status, order: .path, grouping: .none, tree: true)
    #expect(sections.map(\.kind) == [.changes])
    #expect(sections[0].entries.map(\.path) == ["src/main.rs", "src/utils.rs", "tests/main_test.rs"])
  }

  /// Zed `project_diff_path_key`: the key depends only on the file's own
  /// status and path, so staging a file, in a real repository, never
  /// changes where anything is.
  @Test func stagingNeverMovesAFile() async throws {
    let fixture = try FixtureRepository()
    try fixture.commit("base", files: ["b.rs": "1\n", "d.rs": "1\n", "a/x.rs": "1\n"])
    try write(fixture, ["b.rs": "2\n", "d.rs": "2\n", "a/x.rs": "2\n", "c_new.rs": "n\n"])
    let repository = try await GitRepository.open(at: fixture.url)
    func order() async throws -> [String] {
      RepositorySession.mergeUncommitted(
        unstaged: try await repository.workingTreeDiff(staged: false, path: nil),
        staged: try await repository.workingTreeDiff(staged: true, path: nil),
        status: try await repository.status(), order: .path, grouping: .trackedUntracked, tree: false
      ).files.map(\.path)
    }
    let before = try await order()
    #expect(before == ["a/x.rs", "b.rs", "d.rs", "c_new.rs"])
    for path in before {
      try await repository.stage([path])
      #expect(try await order() == before, "staging \(path) moved files")
    }
    for path in before.reversed() {
      try await repository.unstage([path])
      #expect(try await order() == before, "unstaging \(path) moved files")
    }
  }
}
