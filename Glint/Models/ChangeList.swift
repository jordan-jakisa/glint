import Foundation

/// The Changes list and Uncommitted Changes, as Zed's git panel and project
/// diff build them (crates/git_ui: `git_panel.rs`, `project_diff_path_key`
/// in `diff_multibuffer.rs`). One place decides which section a file is in
/// and where it sorts, so the list and the diff never disagree, and a
/// file's place depends only on its own status and path: staging it never
/// moves it.
enum ChangeList {
  struct Section: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case conflicts, tracked, untracked, staged, unstaged, changes }
    let kind: Kind
    let entries: [StagingEntry]
    var id: String { kind.rawValue }
    var title: String {
      switch kind {
      case .conflicts: "Conflicts"
      case .tracked: "Tracked"
      case .untracked: "Untracked"
      case .staged: "Staged"
      case .unstaged: "Unstaged"
      case .changes: "Changes"
      }
    }
  }

  /// What the list shows, section by section. Empty sections are left out.
  /// Grouped by staging, a partly staged file is in both sections, as in
  /// Zed.
  static func sections(
    _ status: WorkingTreeStatus, order: FileOrder = .current, grouping: ChangeGrouping = .current,
    tree: Bool = ChangeGrouping.isTree
  ) -> [Section] {
    let all = status.unsortedEntries
    func sorted(_ entries: [StagingEntry]) -> [StagingEntry] { sort(entries, order: order, tree: tree) }
    let sections: [Section]
    switch grouping {
    case .trackedUntracked:
      sections = [
        Section(kind: .conflicts, entries: sorted(all.filter { $0.section == .conflicts })),
        Section(kind: .tracked, entries: sorted(all.filter { $0.section == .tracked })),
        Section(kind: .untracked, entries: sorted(all.filter { $0.section == .untracked })),
      ]
    case .stagedUnstaged:
      let rest = all.filter { $0.section != .conflicts }
      sections = [
        Section(kind: .conflicts, entries: sorted(all.filter { $0.section == .conflicts })),
        Section(kind: .staged, entries: sorted(rest.filter { $0.state != .none })),
        Section(kind: .unstaged, entries: sorted(rest.filter { $0.state != .all })),
      ]
    case .none:
      sections = [Section(kind: .changes, entries: sorted(all))]
    }
    return sections.filter { !$0.entries.isEmpty }
  }

  /// Uncommitted Changes' file order, Zed's `project_diff_path_key`: grouped
  /// by status (Conflicts, Tracked, Untracked) only when the list is, and
  /// otherwise by the sort alone.
  static func diffOrder(
    _ status: WorkingTreeStatus, order: FileOrder = .current, grouping: ChangeGrouping = .current,
    tree: Bool = ChangeGrouping.isTree
  ) -> [String] {
    if grouping == .trackedUntracked {
      return sections(status, order: order, grouping: grouping, tree: tree).flatMap { $0.entries.map(\.path) }
    }
    return sort(status.unsortedEntries, order: order, tree: tree).map(\.path)
  }

  /// Every file once, top to bottom as the list shows them: what next and
  /// previous walk through.
  static func visibleOrder(
    _ status: WorkingTreeStatus, order: FileOrder = .current, grouping: ChangeGrouping = .current,
    tree: Bool = ChangeGrouping.isTree
  ) -> [StagingEntry] {
    var seen = Set<String>()
    return sections(status, order: order, grouping: grouping, tree: tree)
      .flatMap(\.entries)
      .filter { seen.insert($0.path).inserted }
  }

  static func sort(_ entries: [StagingEntry], order: FileOrder, tree: Bool) -> [StagingEntry] {
    tree ? entries.sorted { FileOrder.treeLess($0.path, $1.path) } : order.sorted(entries, path: \.path)
  }
}
