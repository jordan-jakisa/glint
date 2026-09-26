import Foundation

/// The Changes tab: working-tree status and its selection.
extension RepositorySession {
  /// Rereads `git status`, then reloads the selected working-tree diff in
  /// place. Calls that arrive while one is running collapse into one rerun.
  func refreshWorkingTree() {
    guard let repository else { return }
    if statusTask != nil {
      statusRefreshQueued = true
      return
    }
    statusTask = Task {
      let start = ContinuousClock.now
      let fresh = try? await repository.status()
      if let fresh {
        Timing.report("status", since: start, budget: 50)
        apply(fresh)
      }
      statusTask = nil
      if statusRefreshQueued {
        statusRefreshQueued = false
        refreshWorkingTree()
      }
    }
  }

  func apply(_ fresh: WorkingTreeStatus) {
    let old = status
    status = fresh
    let previousSelection = selectedChange
    reconcileChangeSelection(previous: old)
    // A file on screen may have changed without its status changing, so the
    // diff reloads either way. Same source: keep the reader's place.
    if tab == .changes, selectedChange == previousSelection, selectedChange != nil {
      showSelectedDiff(inPlace: true)
    }
  }

  /// Keeps the selection sensible after status changes behind the user's back:
  /// follow a file that moved between groups, or land on its neighbour when it
  /// has no changes left.
  private func reconcileChangeSelection(previous: WorkingTreeStatus) {
    guard let selection = selectedChange else {
      selectedChange = ChangeSelection.first(in: status)
      return
    }
    let group = selection.staged ? status.staged : status.unstaged
    guard let path = selection.path else {
      if group.isEmpty { selectedChange = ChangeSelection.first(in: status) }
      return
    }
    if group.contains(where: { $0.path == path }) { return }
    let other = selection.staged ? status.unstaged : status.staged
    if other.contains(where: { $0.path == path }) {
      selectedChange = ChangeSelection(staged: !selection.staged, path: path)
      return
    }
    let oldGroup = selection.staged ? previous.staged : previous.unstaged
    let index = oldGroup.firstIndex { $0.path == path } ?? 0
    if group.isEmpty {
      selectedChange = ChangeSelection.first(in: status)
    } else {
      selectedChange = ChangeSelection(staged: selection.staged, path: group[min(index, group.count - 1)].path)
    }
  }

  /// Every selectable file, in list order: staged first, then unstaged.
  var changeSelections: [ChangeSelection] {
    status.staged.map { ChangeSelection(staged: true, path: $0.path) }
      + status.unstaged.map { ChangeSelection(staged: false, path: $0.path) }
  }

  func moveChangeSelection(by offset: Int) {
    let all = changeSelections
    guard !all.isEmpty else { return }
    guard let current = selectedChange, let index = all.firstIndex(of: current) else {
      selectedChange = all.first
      return
    }
    selectedChange = all[min(max(index + offset, 0), all.count - 1)]
  }
}
