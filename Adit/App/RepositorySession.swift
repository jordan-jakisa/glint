import AppKit
import Observation

/// State for one window: the open repository, its commit list, the selected
/// commit's diff, and where the reader is within that diff.
///
/// This is the only type that talks to `GitRepository`. Views read `Models/`
/// values from here and call its methods; they never see the git layer.
@MainActor
@Observable
final class RepositorySession {
  enum Phase: Equatable {
    /// Nothing open. `message` explains why, when a reopen failed.
    case closed(message: String?)
    case opening
    case ready
  }

  private(set) var phase: Phase = .closed(message: nil)
  private(set) var info: RepositoryInfo?
  private(set) var commits: [Commit] = []
  private(set) var hasMoreCommits = false
  /// Shown as an alert. Set when opening a newly picked folder fails while
  /// another repository stays open.
  var alertMessage: String?

  var selectedCommitID: String? {
    didSet {
      guard selectedCommitID != oldValue else { return }
      showDiff(for: selectedCommitID)
    }
  }

  var selectedCommit: Commit? {
    guard let selectedCommitID else { return nil }
    return commits.first { $0.id == selectedCommitID }
  }

  private(set) var diff: CommitDiff? {
    didSet { rebuildRows() }
  }
  private(set) var diffError: String?
  private(set) var isLoadingDiff = false
  private(set) var collapsedFiles: Set<Int> = [] {
    didSet { rebuildRows() }
  }

  /// Unified or split. Remembered between launches.
  var layout: DiffLayout {
    didSet {
      guard layout != oldValue else { return }
      UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
      rebuildRows()
    }
  }

  /// The current diff, flattened for the lazy stack. Rebuilt only when the
  /// diff, layout, or collapsed files change, never while scrolling.
  private(set) var rows: [DiffRow] = []
  /// Bumped with every rebuild, so the table can tell new rows from old
  /// without comparing them.
  private(set) var rowsVersion = 0
  private(set) var lineNumberDigits = 3
  /// Hands keyboard jumps straight to the table, skipping a SwiftUI update.
  @ObservationIgnored let diffScroller = DiffScroller()

  // MARK: - Private state

  private var access = RepositoryAccess()
  @ObservationIgnored private var repository: GitRepository?
  @ObservationIgnored private var isLoadingMore = false
  @ObservationIgnored private var diffTask: Task<Void, Never>?
  @ObservationIgnored private var prefetchTask: Task<Void, Never>?
  @ObservationIgnored private var cache = DiffCache(capacity: 32)
  @ObservationIgnored private var diffRequestedAt: ContinuousClock.Instant?
  /// The reader's position in the diff: the top-most visible row, or the last
  /// place a keyboard jump landed. Not observed: it changes on every scroll.
  @ObservationIgnored private var cursor = DiffRowID.top

  private nonisolated static let firstPageSize = 100
  private static let pageSize = 200
  private static let layoutKey = "diffLayout"

  init() {
    layout = UserDefaults.standard.string(forKey: Self.layoutKey)
      .flatMap(DiffLayout.init(rawValue:)) ?? .unified
  }

  private func rebuildRows() {
    rowsVersion += 1
    guard let diff else {
      rows = []
      return
    }
    rows = DiffRow.build(diff, layout: layout, collapsed: collapsedFiles)
    lineNumberDigits = DiffRow.lineNumberDigits(diff)
  }

  // MARK: - Opening

  /// Everything the first frame needs, loaded in one go off the main actor.
  private struct Opened: Sendable {
    let repository: GitRepository
    let info: RepositoryInfo
    let commits: [Commit]
    let firstDiff: CommitDiff?
  }

  @concurrent
  private nonisolated static func load(_ url: URL) async throws -> Opened {
    let repository = try await GitRepository.open(at: url)
    let info = await repository.info()
    let commits = try await repository.firstCommits(limit: firstPageSize)
    var firstDiff: CommitDiff?
    if let head = commits.first {
      firstDiff = try? await repository.diff(commitID: head.id)
    }
    return Opened(repository: repository, info: info, commits: commits, firstDiff: firstDiff)
  }

  /// The last repository, already opening. Started from `AditApp.init` so git
  /// work overlaps window creation instead of waiting for the window to appear.
  private static var prewarmed: (access: RepositoryAccess, url: URL, load: Task<Opened, Error>)?

  static func prewarm() {
    let access = RepositoryAccess()
    guard let url = access.restore() else { return }
    prewarmed = (access, url, Task { try await load(url) })
  }

  /// Reopens the repository from last launch, if there was one.
  func restoreLastRepository() {
    guard case .closed = phase else { return }
    if let prewarmed = Self.prewarmed {
      Self.prewarmed = nil
      access = prewarmed.access
      open(prewarmed.url, restoring: true, loading: prewarmed.load)
    } else if let url = access.restore() {
      open(url, restoring: true, loading: Task { try await Self.load(url) })
    }
  }

  func chooseRepository() {
    guard let url = access.choose() else { return }
    open(url, restoring: false, loading: Task { try await Self.load(url) })
  }

  private func open(_ url: URL, restoring: Bool, loading: Task<Opened, Error>) {
    if repository == nil { phase = .opening }
    Task {
      do {
        let opened = try await loading.value
        access.adopt(url)
        install(opened)
      } catch {
        let message = "\(url.lastPathComponent): \(error)"
        if restoring {
          access.forget()
          phase = .closed(message: "Couldn't reopen \(message)")
        } else if repository == nil {
          phase = .closed(message: "Couldn't open \(message)")
        } else {
          alertMessage = "Couldn't open \(message)"
        }
      }
    }
  }

  private func install(_ opened: Opened) {
    diffTask?.cancel()
    prefetchTask?.cancel()
    repository = opened.repository
    info = opened.info
    commits = opened.commits
    hasMoreCommits = opened.commits.count == Self.firstPageSize
    cache = DiffCache(capacity: 32)
    if let firstDiff = opened.firstDiff { cache[firstDiff.commitID] = firstDiff }
    diff = nil
    diffError = nil
    phase = .ready
    selectedCommitID = opened.commits.first?.id
    // The first diff paints with the window; the launch budget covers it.
    diffRequestedAt = nil
    if Self.isBenchmarking { Task { await runBenchmark() } }
  }

  /// Rereads HEAD, and the first page of history if HEAD moved. Cheap enough to
  /// run every time the app comes forward, so new commits show up unasked.
  func refresh() {
    guard let repository, phase == .ready, !isLoadingMore else { return }
    Task {
      let info = await repository.info()
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

  // MARK: - Commit list

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

  func selectNextCommit() { moveSelection(by: 1) }
  func selectPreviousCommit() { moveSelection(by: -1) }

  private func moveSelection(by offset: Int) {
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

  // MARK: - Diff loading

  private func showDiff(for commitID: String?) {
    diffTask?.cancel()
    cursor = .top
    if !collapsedFiles.isEmpty { collapsedFiles = [] }
    diffError = nil
    diffRequestedAt = .now
    guard let commitID, let repository else {
      diff = nil
      return
    }
    if let cached = cache[commitID] {
      diff = cached
      isLoadingDiff = false
      prefetch(after: commitID)
      return
    }
    // Keep the previous diff on screen until the new one is ready. Most loads
    // finish inside a frame or two, and a blank flash reads as slower.
    isLoadingDiff = true
    diffTask = Task {
      do {
        let loaded = try await repository.diff(commitID: commitID)
        cache[commitID] = loaded
        guard !Task.isCancelled, selectedCommitID == commitID else { return }
        diff = loaded
        isLoadingDiff = false
        prefetch(after: commitID)
      } catch is CancellationError {
      } catch {
        guard selectedCommitID == commitID else { return }
        diff = nil
        diffError = "\(error)"
        isLoadingDiff = false
      }
    }
  }

  /// Builds the next commit's diff in the background, so `j` usually finds it
  /// already cached.
  private func prefetch(after commitID: String) {
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

  /// Called by the diff view once the selected diff is on screen.
  func diffDidAppear(_ commitID: String) {
    guard let start = diffRequestedAt, commitID == selectedCommitID else { return }
    diffRequestedAt = nil
    let lines = diff?.files.reduce(0) { $0 + $1.additions + $1.deletions } ?? 0
    if lines > 10_000 {
      Timing.report("select to diff painted (large diff)", since: start, budget: 100)
    } else {
      Timing.report("select to diff painted", since: start, budget: 50)
    }
  }

  // MARK: - Diff navigation

  func toggleLayout() {
    layout = layout == .unified ? .split : .unified
  }

  func toggleCollapsed(_ fileID: Int) {
    if collapsedFiles.remove(fileID) == nil { collapsedFiles.insert(fileID) }
  }

  func toggleCurrentFileCollapsed() {
    guard diff?.files.isEmpty == false else { return }
    toggleCollapsed(cursor.file)
    scroll(to: .file(cursor.file))
  }

  /// Called as the diff scrolls, with the rows now on screen.
  func visibleRowsChanged(_ rows: [DiffRowID]) {
    if let top = rows.min() { cursor = top }
  }

  func nextFile() {
    guard let files = diff?.files, cursor.file + 1 < files.count else { return }
    scroll(to: .file(cursor.file + 1))
  }

  func previousFile() {
    guard let files = diff?.files, !files.isEmpty else { return }
    // Inside a file, go back to its header first, like previous-hunk does.
    let target = cursor.hunk >= 0 ? cursor.file : max(cursor.file - 1, 0)
    scroll(to: .file(target))
  }

  func nextHunk() {
    guard let target = hunkAnchors().first(where: { $0 > cursor }) else { return }
    collapsedFiles.remove(target.file)
    scroll(to: target)
  }

  func previousHunk() {
    guard let target = hunkAnchors().last(where: { $0 < cursor }) else { return }
    collapsedFiles.remove(target.file)
    scroll(to: target)
  }

  private func hunkAnchors() -> [DiffRowID] {
    guard let files = diff?.files else { return [] }
    return files.flatMap { file in file.hunks.map { DiffRowID.hunk(file.id, $0.id) } }
  }

  private func scroll(to target: DiffRowID) {
    cursor = target
    diffScroller.scroll(to: target, rowsVersion: rowsVersion)
  }
}

/// Recently built diffs, so moving back and forth between commits is instant.
/// Commits are immutable, so an entry never goes stale.
private struct DiffCache {
  let capacity: Int
  private var entries: [String: CommitDiff] = [:]
  private var order: [String] = []

  init(capacity: Int) { self.capacity = capacity }

  subscript(id: String) -> CommitDiff? {
    get { entries[id] }
    set {
      guard let newValue else { return }
      if entries.updateValue(newValue, forKey: id) == nil { order.append(id) }
      if order.count > capacity { entries[order.removeFirst()] = nil }
    }
  }
}
