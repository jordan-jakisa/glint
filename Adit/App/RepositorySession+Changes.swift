import AppKit

/// The Changes tab: working-tree status and its selection.
extension RepositorySession {
  /// Rereads `git status`, then reloads the selected working-tree diff in
  /// place. Calls that arrive while one is running collapse into one rerun.
  /// `changedAt` is when the file watcher first saw the change, for timing.
  func refreshWorkingTree(changedAt: ContinuousClock.Instant? = nil) {
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
        if let changedAt {
          // Plus FSEvents' 50 ms latency before the watcher hears about it.
          Timing.report("file event to list updated", since: changedAt, budget: 150)
        }
      }
      statusTask = nil
      if statusRefreshQueued {
        statusRefreshQueued = false
        refreshWorkingTree()
      }
    }
  }

  func apply(_ fresh: WorkingTreeStatus, reloadDiff: Bool = true) {
    let old = status
    status = fresh
    let previousSelection = selectedChange
    reconcileChangeSelection(previous: old)
    // A file on screen may have changed without its status changing, so the
    // diff reloads either way. Same source: keep the reader's place.
    if reloadDiff, tab == .changes, selectedChange == previousSelection, selectedChange != nil {
      showSelectedDiff(inPlace: true)
    }
  }

  // MARK: - Staging

  /// Stages or unstages one whole file. The list updates this frame; the index
  /// write and a real status refresh follow.
  func setStaged(_ path: String, _ staged: Bool) {
    if staged {
      changeIndex({ $0.markStaged(path) }) { try await $0.stage([path]) }
    } else {
      changeIndex({ $0.markUnstaged(path) }) { try await $0.unstage([path]) }
    }
  }

  /// Space on the selected file: flip it to the other group and move on to
  /// the next file in this one, so you can go down the list staging.
  func toggleSelectedStaged() {
    guard tab == .changes, let selection = selectedChange else { return }
    guard let path = selection.path else {
      selection.staged ? unstageAll() : stageAll()
      return
    }
    let group = selection.staged ? status.staged : status.unstaged
    let index = group.firstIndex { $0.path == path } ?? 0
    let rest = group.filter { $0.path != path }
    setStaged(path, !selection.staged)
    if rest.isEmpty {
      selectedChange = ChangeSelection(staged: !selection.staged, path: path)
    } else {
      selectedChange = ChangeSelection(staged: selection.staged, path: rest[min(index, rest.count - 1)].path)
    }
  }

  func stageAll() {
    let paths = status.unstaged.map(\.path)
    guard !paths.isEmpty else { return }
    changeIndex({ status in paths.forEach { status.markStaged($0) } }) { try await $0.stageAll() }
  }

  func unstageAll() {
    let paths = status.staged.map(\.path)
    guard !paths.isEmpty else { return }
    changeIndex({ status in paths.forEach { status.markUnstaged($0) } }) { try await $0.unstage(paths) }
  }

  private func changeIndex(
    _ optimistic: (inout WorkingTreeStatus) -> Void,
    _ work: @escaping @Sendable (GitRepository) async throws -> Void
  ) {
    guard let repository else { return }
    var next = status
    optimistic(&next)
    apply(next, reloadDiff: false)
    Task {
      let start = ContinuousClock.now
      do {
        try await work(repository)
        Timing.report("index write", since: start, budget: 100)
      } catch {
        alertMessage = "\(error)"
      }
      refreshWorkingTree()
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

  // MARK: - Files

  func revealInFinder(_ path: String) {
    guard let repository else { return }
    NSWorkspace.shared.activateFileViewerSelecting([repository.url.appendingPathComponent(path)])
  }

  func copyPath(_ path: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
  }
}
