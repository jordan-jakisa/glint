import Foundation

/// A folder holding several repositories: switching the active one, and
/// routing file events to the repository they belong to.
extension RepositorySession {
  /// The workspace entry for the active repository.
  var activeWorkspaceRepository: WorkspaceRepository? {
    guard let workspace, let url = repository?.url.standardizedFileURL else { return nil }
    return workspace.repositories.first { $0.url.standardizedFileURL == url }
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

  /// Hook for the picker's counts; filled in with the repository picker.
  func otherRepositoriesChanged(_ paths: [String]) {}
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
