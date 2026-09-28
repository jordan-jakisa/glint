import AppKit

/// The Changes tab: working-tree status and its selection.
extension RepositorySession {
  /// Rereads `git status`, then reloads the selected working-tree diff in
  /// place. With `paths` (repository-relative, from the file watcher) only
  /// those files are checked and merged in; without, it's a full scan.
  /// Requests that arrive while one runs are merged into one rerun.
  /// `changedAt` is when the watcher first saw the change, for timing.
  func refreshWorkingTree(changedAt: ContinuousClock.Instant? = nil, paths: Set<String>? = nil) {
    guard let repository else { return }
    if statusTask != nil {
      // Any full request wins; otherwise the paths add up.
      if let paths, pendingStatusPaths != nil || !statusRefreshQueued {
        pendingStatusPaths = (pendingStatusPaths ?? []).union(paths)
      } else {
        pendingStatusPaths = nil
      }
      statusRefreshQueued = true
      return
    }
    let partial = paths.map { Array($0) }
    statusTask = Task {
      let start = ContinuousClock.now
      let fresh = try? await repository.status(paths: partial)
      if let fresh {
        if let paths {
          Timing.report("status, changed files only", since: start, budget: 16)
          apply(status.merging(fresh, for: paths))
        } else {
          Timing.report("status", since: start, budget: 50)
          apply(fresh)
        }
        if let changedAt {
          // Plus FSEvents' 50 ms latency before the watcher hears about it.
          Timing.report("file event to list updated", since: changedAt, budget: 150)
        }
      }
      statusTask = nil
      if statusRefreshQueued {
        statusRefreshQueued = false
        let queued = pendingStatusPaths
        pendingStatusPaths = nil
        refreshWorkingTree(paths: queued)
      }
    }
  }

  func apply(_ fresh: WorkingTreeStatus, reloadDiff: Bool = true) {
    let old = status
    status = fresh
    updateActiveSummary()
    loadLineStats()
    let previousSelection = selectedChange
    reconcileChangeSelection(previous: old)
    // A file on screen may have changed without its status changing, so the
    // diff reloads either way. Same source: keep the reader's place.
    if reloadDiff, tab == .changes, selectedChange == previousSelection, selectedChange != nil {
      showSelectedDiff(inPlace: true)
    }
    // The branch diff includes uncommitted work, so it follows edits live.
    if reloadDiff, showsBranchDiff { showSelectedDiff(inPlace: true) }
  }

  // MARK: - Staging

  /// Stages or unstages one whole file. The list updates this frame; the index
  /// write and a real status refresh follow.
  func setStaged(_ path: String, _ staged: Bool) {
    Timing.writes.notice("\(staged ? "stage" : "unstage", privacy: .public) \(path, privacy: .private)")
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
    setStaged(path, !selection.staged)
  }

  func stageAll() {
    let paths = status.unstaged.map(\.path)
    guard !paths.isEmpty else { return }
    Timing.writes.notice("stage all (\(paths.count) files)")
    changeIndex({ status in paths.forEach { status.markStaged($0) } }) { try await $0.stageAll() }
  }

  func unstageAll() {
    let paths = status.staged.map(\.path)
    guard !paths.isEmpty else { return }
    Timing.writes.notice("unstage all (\(paths.count) files)")
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
        alert = UserAlert("Couldn't update what's staged", error: error)
      }
      refreshWorkingTree()
    }
  }

  /// Keeps the selection sensible after status changes: when the selected
  /// file leaves its group (staged, unstaged, or discarded), move to its
  /// neighbour in that group, so you can keep working down the list. Only when
  /// the group is empty does the selection follow the file to the other one.
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
    if !group.isEmpty {
      let oldGroup = selection.staged ? previous.staged : previous.unstaged
      let index = oldGroup.firstIndex { $0.path == path } ?? 0
      selectedChange = ChangeSelection(staged: selection.staged, path: group[min(index, group.count - 1)].path)
      return
    }
    let other = selection.staged ? status.unstaged : status.staged
    if other.contains(where: { $0.path == path }) {
      selectedChange = ChangeSelection(staged: !selection.staged, path: path)
    } else {
      selectedChange = ChangeSelection.first(in: status)
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

  // MARK: - Discarding

  /// Asks before discarding: the one action here that can lose work.
  func requestDiscard(_ paths: [String]) {
    let files = status.unstaged.filter { paths.contains($0.path) && $0.kind != .conflicted }
    guard !files.isEmpty else { return }
    pendingDiscard = files
  }

  func requestDiscardAll() {
    requestDiscard(status.unstaged.map(\.path))
  }

  func confirmDiscard() {
    guard let files = pendingDiscard, let repository else { return }
    pendingDiscard = nil
    Timing.writes.notice("discard (\(files.count) files)")
    let tracked = files.filter { $0.kind != .untracked }.map(\.path)
    let untracked = files.filter { $0.kind == .untracked }.map { repository.url.appendingPathComponent($0.path) }
    var next = status
    next.unstaged.removeAll { file in files.contains { $0.path == file.path } }
    apply(next, reloadDiff: false)
    Task {
      do {
        try await repository.discard(tracked)
        // Untracked files aren't in git at all, so git can't bring them back.
        // The Trash can.
        for url in untracked {
          try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
      } catch {
        alert = UserAlert("Couldn't discard that", error: error)
      }
      refreshWorkingTree()
    }
  }

  // MARK: - Line counts

  /// Each changed file's `+N -N` against the last commit, for Style Zed's
  /// list, like Zed's diff stats. Only loaded there, off the main thread.
  /// Each changed file's `+N -N` against the last commit, for Style Zed's
  /// list, like Zed's diff stats: staged plus unstaged lines, counted by
  /// libgit2 off the main thread. Only loaded in Style Zed. New untracked
  /// files show none, as in Zed.
  func loadLineStats() {
    guard Theme.shared.isZed, let repository else { return }
    let untracked = Set(status.unstaged.filter { $0.kind == .untracked }.map(\.path))
    Task {
      let unstaged = try? await repository.workingTreeDiff(staged: false, path: nil)
      let staged = try? await repository.workingTreeDiff(staged: true, path: nil)
      // A repository switch mid-load: these counts belong to the old one.
      guard self.repository?.url == repository.url else { return }
      var stats: [String: LineStat] = [:]
      for file in (unstaged?.files ?? []) + (staged?.files ?? []) {
        guard let path = file.newPath ?? file.oldPath, !untracked.contains(path) else { continue }
        let before = stats[path] ?? LineStat(added: 0, deleted: 0)
        stats[path] = LineStat(added: before.added + file.additions, deleted: before.deleted + file.deletions)
      }
      lineStats = stats
    }
  }

  // MARK: - Files

  func revealInFinder(_ path: String) {
    guard let repository else { return }
    NSWorkspace.shared.activateFileViewerSelecting([repository.url.appendingPathComponent(path)])
  }

  /// Opens the file in the app macOS uses for it, like Zed's Open File.
  func openFile(_ path: String) {
    guard let repository else { return }
    NSWorkspace.shared.open(repository.url.appendingPathComponent(path))
  }

  func copyPath(_ path: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(path, forType: .string)
  }
}
