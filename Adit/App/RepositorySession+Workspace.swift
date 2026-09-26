import Foundation

/// A folder holding several repositories: switching the active one, and
/// routing file events to the repository they belong to.
extension RepositorySession {
  /// The workspace entry for the active repository.
  var activeWorkspaceRepository: WorkspaceRepository? {
    guard let workspace, let url = repository?.url.standardizedFileURL else { return nil }
    return workspace.repositories.first { $0.url.standardizedFileURL == url }
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
        alertMessage = "Couldn't open \(target.name).\n\n\(error)"
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
    guard let active = repository?.url.standardizedFileURL.path else { return }
    guard workspace != nil else {
      if change.head { refreshHistory() }
      if change.workingTree { refreshWorkingTree(changedAt: change.firstEventAt) }
      return
    }
    let prefix = active.hasSuffix("/") ? active : active + "/"
    let mine = change.paths.filter { $0.key.hasPrefix(prefix) || $0.key == active }
    if mine.values.contains(.head) { refreshHistory() }
    if !mine.isEmpty { refreshWorkingTree(changedAt: change.firstEventAt) }
    if mine.count < change.paths.count { otherRepositoriesChanged(Array(change.paths.keys)) }
  }

  /// Files changed in repositories other than the active one: refresh just
  /// their summaries.
  func otherRepositoriesChanged(_ paths: [String]) {
    guard let workspace else { return }
    let touched = workspace.repositories.filter { repo in
      let prefix = repo.url.standardizedFileURL.path + "/"
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
