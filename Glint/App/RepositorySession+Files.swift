import AppKit

/// The Files tab: every file in the project, and one open in the editor.
extension RepositorySession {
  /// Where the Files tab's paths start: the folder of repositories when
  /// one is open, else the repository.
  var filesRoot: URL? { workspace?.root ?? repository?.url }

  /// The open repository's folder within `filesRoot`, with a trailing
  /// slash, or "" when the repository is the root.
  var activeFilesPrefix: String {
    guard workspace != nil, let path = activeWorkspaceRepository?.relativePath, !path.isEmpty else { return "" }
    return path + "/"
  }

  /// Rereads the file list: what each repository's index tracks, plus its
  /// untracked files, minus ones deleted on disk. Ignored files never
  /// appear. In a folder of repositories each one is a folder here, beside
  /// any loose files at the top.
  func loadProjectFiles() {
    guard let repository, let root = filesRoot else { return }
    let workspace = self.workspace
    let prefix = activeFilesPrefix
    let untracked = status.unstaged.filter { $0.kind == .untracked }.map { prefix + $0.path }
    let deleted = Set(status.unstaged.filter { $0.kind == .deleted }.map { prefix + $0.path })
    let others = (workspace?.repositories ?? []).filter { $0.url.standardizedFileURL != repository.url.standardizedFileURL }
    let otherUntracked = others.map { other in
      (repositorySummaries[other.relativePath]?.status.unstaged ?? []).filter { $0.kind == .untracked }.map(\.path)
    }
    let showsIgnored = UserDefaults.standard.object(forKey: "filesShowIgnored") as? Bool ?? true
    Task {
      var files = Set((try? await repository.trackedPaths())?.map { prefix + $0 } ?? []).union(untracked)
      var ignored = showsIgnored ? ((try? await repository.ignoredPaths()) ?? []).map { prefix + $0 } : []
      // The open repository first, so the list shows up at once; the others
      // join as they're read.
      if !others.isEmpty { publish(files, ignored: ignored, deleted: deleted, for: repository) }
      for (other, untracked) in zip(others, otherUntracked) {
        guard let opened = try? await GitRepository.open(at: other.url) else { continue }
        let tracked = (try? await opened.trackedPaths()) ?? []
        files.formUnion((tracked + untracked).map { other.relativePath + "/" + $0 })
        if showsIgnored {
          ignored += ((try? await opened.ignoredPaths()) ?? []).map { other.relativePath + "/" + $0 }
        }
      }
      if workspace != nil {
        // Loose files beside the repositories.
        let loose = (try? FileManager.default.contentsOfDirectory(
          at: root, includingPropertiesForKeys: [.isRegularFileKey]))?
          .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
          .map(\.lastPathComponent)
          .filter { $0 != ".DS_Store" } ?? []
        files.formUnion(loose)
      }
      publish(files, ignored: ignored, deleted: deleted, for: repository)
    }
  }

  private func publish(_ files: Set<String>, ignored: [String], deleted: Set<String>, for repository: GitRepository) {
    guard self.repository === repository else { return }
    let folders = Set(ignored.filter { $0.hasSuffix("/") }.map { String($0.dropLast()) })
    let ignoredFiles = Set(ignored.filter { !$0.hasSuffix("/") })
    let sorted = files.union(ignoredFiles).subtracting(deleted)
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    if sorted != projectFiles { projectFiles = sorted }
    if ignoredFiles != self.ignoredFiles { self.ignoredFiles = ignoredFiles }
    if folders != ignoredFolders { ignoredFolders = folders }
  }

  /// Opens `path` in the Files tab's editor. What you had open is saved
  /// first if you changed it. A file too big or not text goes to its
  /// default app instead.
  func showFile(_ path: String) {
    guard let root = filesRoot, path != openedFilePath else { return }
    let url = root.appendingPathComponent(path)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
    guard size <= 2_000_000, let content = try? String(contentsOf: url, encoding: .utf8) else {
      NSWorkspace.shared.open(url)
      return
    }
    closeOpenedFile()
    let edit = LiveEdit(url: url, content: content, start: 0, count: LiveEdit.split(content).lines.count, wholeFile: true)
    edit.startWatching()
    openedFile = edit
    openedFilePath = path
    tab = .files
  }

  /// ⌘S in the Files tab.
  func saveOpenedFile() {
    guard let openedFile else { return }
    do {
      try openedFile.save()
      Timing.writes.notice("save file")
    } catch {
      alert = UserAlert("Couldn't save \(openedFile.fileName)", error: error)
    }
  }

  /// Saves what you changed, then closes the editor.
  func closeOpenedFile() {
    guard let openedFile else { return }
    if openedFile.hasUnsavedChanges { saveOpenedFile() }
    openedFile.stopWatching()
    self.openedFile = nil
    openedFilePath = nil
  }
}
