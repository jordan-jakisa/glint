import Foundation

/// The History tab: paging through commits and moving the selection.
extension RepositorySession {
  /// Rereads HEAD, and the first page of history if HEAD moved.
  func refreshHistory() {
    guard let repository, !isLoadingMore else { return }
    Task {
      let info = await repository.info()
      sync = await repository.syncStatus()
      let head = await repository.headCommitID()
      guard info != self.info || head != commits.first?.id else { return }
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

  func moveCommitSelection(by offset: Int) {
    guard !commits.isEmpty else { return }
    guard let current = selectedCommitID, let index = commits.firstIndex(where: { $0.id == current })
    else {
      selectedCommitID = commits.first?.id
      return
    }
    let next = min(max(index + offset, 0), commits.count - 1)
    selectedCommitID = commits[next].id
    // Page in more history before the reader reaches the end of it.
    if commits.count - next < 20 { loadMoreCommits() }
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
