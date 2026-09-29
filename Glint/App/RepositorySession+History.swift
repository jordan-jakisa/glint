import Foundation

/// The History tab: paging through commits and moving the selection.
extension RepositorySession {
  /// Rereads HEAD, and the first page of history if HEAD moved.
  func refreshHistory() {
    guard let repository, !isLoadingMore else { return }
    Task {
      let info = await repository.info()
      sync = await repository.syncStatus()
      branchBaseName = await repository.branchBase()?.name
      let head = await repository.headCommitID()
      guard info != self.info || head != commits.first?.id else { return }
      // A new commit moves the branch diff too.
      if showsBranchDiff { showSelectedDiff(inPlace: true) }
      guard let fresh = try? await repository.firstCommits(limit: Self.firstPageSize) else { return }
      self.info = info
      commits = fresh
      hasMoreCommits = fresh.count == Self.firstPageSize
      if let selectedCommitID, fresh.contains(where: { $0.id == selectedCommitID }) { return }
      selectedCommitID = fresh.first?.id
    }
  }

  func loadMoreCommits() {
    guard let repository, hasMoreCommits, !isLoadingMore else { return }
    isLoadingMore = true
    Task {
      defer { isLoadingMore = false }
      guard let more = try? await repository.moreCommits(limit: Self.pageSize) else { return }
      commits.append(contentsOf: more)
      hasMoreCommits = more.count == Self.pageSize
    }
  }

  /// History's rows: the pinned branch diff (when there's a base), then
  /// commits; only the file's commits while History is narrowed to a file.
  var historyIDs: [String] {
    guard historyPath == nil else { return fileCommits.map(\.id) }
    return (branchBaseName == nil ? [] : [Self.branchSelectionID]) + commits.map(\.id)
  }

  /// The commits History lists right now.
  var visibleCommits: [Commit] { historyPath == nil ? commits : fileCommits }

  /// Zed's View File History: History narrowed to the commits that touched
  /// `path`, following renames.
  func showHistory(for path: String) {
    guard let repository else { return }
    tab = .history
    historyPath = path
    fileCommits = []
    let git = SystemGit(directory: repository.url)
    Task {
      do {
        let output = try await git.run([
          "log", "--follow", "-n", "500", "--format=%H%x1f%s%x1f%an%x1f%at", "--", path,
        ])
        guard historyPath == path else { return }
        fileCommits = output.split(separator: "\n").compactMap { line in
          let fields = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
          guard fields.count == 4, let seconds = TimeInterval(fields[3]) else { return nil }
          return Commit(id: fields[0], summary: fields[1], authorName: fields[2], date: Date(timeIntervalSince1970: seconds))
        }
        selectedCommitID = fileCommits.first?.id
      } catch {
        alert = UserAlert("Couldn't read the history of \((path as NSString).lastPathComponent)", error: error)
      }
    }
  }

  func clearHistoryFilter() {
    historyPath = nil
    fileCommits = []
    selectedCommitID = commits.first?.id
  }

  var showsBranchDiff: Bool { tab == .history && selectedCommitID == Self.branchSelectionID }

  func moveCommitSelection(by offset: Int) {
    let ids = historyIDs
    guard !ids.isEmpty else { return }
    guard let current = selectedCommitID, let index = ids.firstIndex(of: current) else {
      selectedCommitID = commits.first?.id ?? ids.first
      return
    }
    let next = min(max(index + offset, 0), ids.count - 1)
    selectedCommitID = ids[next]
    // Page in more history before the reader reaches the end of it.
    if ids.count - next < 20 { loadMoreCommits() }
  }

  /// Builds the next commit's diff in the background, so `j` usually finds it
  /// already cached.
  func prefetch(after commitID: String) {
    prefetchTask?.cancel()
    guard let repository, let index = commits.firstIndex(where: { $0.id == commitID }),
      index + 1 < commits.count
    else { return }
    let next = commits[index + 1].id
    guard cache[next] == nil else { return }
    prefetchTask = Task(priority: .utility) {
      guard let loaded = try? await repository.diff(commitID: next) else { return }
      cache[next] = loaded
    }
  }
}
