import Foundation

/// A folder holding several repositories: switching the active one, and
/// routing file events to the repository they belong to.
extension RepositorySession {
  /// The workspace entry for the active repository.
  var activeWorkspaceRepository: WorkspaceRepository? {
    guard let workspace, let url = repository?.url.standardizedFileURL else { return nil }
    return workspace.repositories.first { $0.url.standardizedFileURL == url }
  }

  /// The other repositories with changes, in workspace order, for the
  /// all-repositories view. Empty unless that view is on.
  var otherRepositoryChanges: [(repository: WorkspaceRepository, files: [ChangeSelection], kinds: [String: ChangedFile.Kind])] {
    guard showsAllRepositories, let workspace else { return [] }
    let active = activeWorkspaceRepository?.relativePath
    return workspace.repositories.compactMap { repository in
      guard repository.relativePath != active, let summary = repositorySummaries[repository.relativePath],
        summary.changeCount > 0
      else { return nil }
      // One row per file: its unstaged change if it has one, else its staged one.
      var files: [ChangeSelection] = []
      var kinds: [String: ChangedFile.Kind] = [:]
      for file in summary.status.unstaged {
        files.append(ChangeSelection(staged: false, path: file.path))
        kinds[file.path] = file.kind
      }
      for file in summary.status.staged where kinds[file.path] == nil {
        files.append(ChangeSelection(staged: true, path: file.path))
        kinds[file.path] = file.kind
      }
      return (repository, files, kinds)
    }
  }

  /// The active repository's folder, for the terminal panel.
  var repositoryURL: URL? { info?.url }

  /// Fills the diff's space with the terminal, showing it first if it's
  /// hidden, or puts it back under the diff.
  func toggleTerminalMaximized() {
    if isTerminalMaximized {
      isTerminalMaximized = false
    } else {
      isTerminalShown = true
      isTerminalMaximized = true
    }
  }

  /// Opens another shell in the terminal panel, showing it if hidden.
  func newTerminalTab() {
    guard let folder = repository?.url else { return }
    if isTerminalShown { terminals.newTab(for: folder) } else { isTerminalShown = true }
  }

  /// Closes the terminal pane you're in, and its tab with its last pane;
  /// closing the last tab hides the panel.
  func closeTerminalPane() {
    guard isTerminalShown, let folder = repository?.url else { return }
    if !terminals.closePane(in: folder) { isTerminalShown = false }
  }

  /// Splits the terminal pane you're in, showing the panel first if hidden.
  /// Under the diff the panel is short, so stacking panes there first
  /// expands the terminal; side by side works at any height.
  func splitTerminal(_ axis: SplitAxis) {
    guard let folder = repository?.url else { return }
    let wasShown = isTerminalShown
    isTerminalShown = true
    if axis == .vertical { isTerminalMaximized = true }
    // A hidden panel with no shell yet starts one on showing; that's the split.
    if wasShown || terminals.current(for: folder) != nil { terminals.split(axis, in: folder) }
  }

  func focusTerminalPane(_ direction: PaneDirection) {
    guard isTerminalShown, let folder = repository?.url else { return }
    terminals.moveFocus(direction, in: folder)
  }

  /// Opens the active repository in your terminal app (⌘T).
  func openInTerminal() {
    guard let folder = repository?.url else { return }
    let app = TerminalApp.preferred
    Task {
      do {
        try await app.open(at: folder)
      } catch {
        alert = UserAlert("Couldn't open \(app.name)", error: error)
      }
    }
  }

  /// A dot beside the repository name says another repository has changes.
  var otherRepositoriesHaveChanges: Bool {
    let active = activeWorkspaceRepository?.relativePath
    return repositorySummaries.contains { $0.key != active && $0.value.changeCount > 0 }
  }

  /// Makes another repository of the workspace the active one. Everything
  /// (Changes, History, the commit box, branches, sync) follows it. With
  /// `selecting`, lands on that file.
  func switchRepository(to target: WorkspaceRepository, selecting file: ChangeSelection? = nil) {
    guard let workspace else { return }
    if target.url.standardizedFileURL == repository?.url.standardizedFileURL {
      if let file { selectedChange = file }
      return
    }
    let start = ContinuousClock.now
    Timing.writes.notice("switch repository")
    Task {
      do {
        let opened = try await Self.load(target.url, in: workspace)
        install(opened, selecting: file)
        Timing.report("switch repository", since: start, budget: 100)
      } catch {
        alert = UserAlert("Couldn't open \(target.name)", error: error)
      }
    }
  }

  /// Switches to the workspace's nth repository (0-based), for ⌘1 to ⌘9.
  func switchRepository(at index: Int) {
    guard let repositories = workspace?.repositories, repositories.indices.contains(index) else { return }
    switchRepository(to: repositories[index])
  }

  /// Routes a burst of file events. In a workspace, only events inside the
  /// active repository refresh it; the others update the picker's counts.
  func filesChanged(_ change: RepositoryWatcher.Change) {
    // FSEvents reports real paths (/private/var/...); the repository may have
    // been opened through a symlink (/var/...). Compare real paths.
    guard let active = repository?.url.resolvingSymlinksInPath().path else { return }
    let prefix = active.hasSuffix("/") ? active : active + "/"
    let mine = change.paths.filter { $0.key.hasPrefix(prefix) || $0.key == active }
    if mine.values.contains(.head) { refreshHistory() }
    if !mine.isEmpty {
      // Only working-tree files changed: check just those. The index or HEAD
      // changing (staging, commits, checkouts) can touch anything: full scan.
      let files = mine.keys.filter { !$0.contains("/.git/") && !$0.hasSuffix("/.git") }
      let onlyFiles = files.count == mine.count && files.count <= 500
      let relative = Set(files.map { String($0.dropFirst(prefix.count)) })
      refreshWorkingTree(changedAt: change.firstEventAt, paths: onlyFiles ? relative : nil)
    }
    if mine.count < change.paths.count { otherRepositoriesChanged(Array(change.paths.keys)) }
  }

  /// Files changed in repositories other than the active one: refresh just
  /// their summaries.
  func otherRepositoriesChanged(_ paths: [String]) {
    guard let workspace else { return }
    let touched = workspace.repositories.filter { repo in
      let prefix = repo.url.resolvingSymlinksInPath().path + "/"
      return paths.contains { $0.hasPrefix(prefix) }
    }
    let active = activeWorkspaceRepository?.relativePath
    let others = Set(touched.map(\.relativePath)).subtracting(active.map { [$0] } ?? [])
    if !others.isEmpty { refreshSummaries(of: others) }
  }

  /// The active repository's summary comes straight from what's on screen.
  func updateActiveSummary() {
    guard let active = activeWorkspaceRepository else { return }
    repositorySummaries[active.relativePath] = RepositorySummary(branch: info?.branch, status: status)
  }

  /// Rereads branch and status for the workspace's other repositories (or
  /// just `only`), in the background, one at a time so they don't compete
  /// with the active repository for disk.
  func refreshSummaries(of only: Set<String>?) {
    guard let workspace else { return }
    let active = activeWorkspaceRepository?.relativePath
    let targets = workspace.repositories.filter {
      $0.relativePath != active && (only?.contains($0.relativePath) ?? true)
    }
    guard !targets.isEmpty else { return }
    let previous = summaryTask
    summaryTask = Task(priority: .utility) {
      await previous?.value
      let start = ContinuousClock.now
      for target in targets {
        guard self.workspace == workspace else { return }
        do {
          let handle: GitRepository
          if let existing = summaryHandles[target.relativePath] {
            handle = existing
          } else {
            handle = try await GitRepository.open(at: target.url)
            summaryHandles[target.relativePath] = handle
          }
          let branch = await handle.info().branch
          let status = try await handle.status()
          repositorySummaries[target.relativePath] = RepositorySummary(branch: branch, status: status)
        } catch {
          continue
        }
      }
      if only == nil { Timing.report("workspace status, other repositories", since: start, budget: 150) }
    }
  }
}

/// Which repository of each workspace was active last, so reopening a
/// workspace lands where you left it.
enum WorkspaceMemory {
  private static let key = "workspaceActiveRepositories"

  static func activeRepository(in root: URL) -> String? {
    (UserDefaults.standard.dictionary(forKey: key) as? [String: String])?[root.standardizedFileURL.path]
  }

  static func remember(_ relativePath: String, in root: URL) {
    var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    all[root.standardizedFileURL.path] = relativePath
    UserDefaults.standard.set(all, forKey: key)
  }
}
