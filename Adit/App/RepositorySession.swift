import AppKit
import Observation

/// State for one window: the open repository, its working-tree changes and
/// history, the diff on screen, and where the reader is within it.
///
/// This is the only type that talks to `GitRepository`. Views read `Models/`
/// values from here and call its methods; they never see the git layer. The
/// methods live in extensions by area: `+Changes`, `+History`, `+Navigation`.
@MainActor
@Observable
final class RepositorySession {
  enum Phase: Equatable {
    /// Nothing open. `message` explains why, when a reopen failed.
    case closed(message: String?)
    case opening
    case ready
  }

  enum Tab: String {
    case changes, history
  }

  private(set) var phase: Phase = .closed(message: nil)
  internal(set) var info: RepositoryInfo?
  /// Shown as an alert: failures of actions the user asked for.
  var alertMessage: String?

  /// Each tab keeps its own selection; switching tabs shows that tab's diff.
  var tab: Tab = .changes {
    didSet { if tab != oldValue { showSelectedDiff() } }
  }

  // MARK: Changes tab

  internal(set) var status = WorkingTreeStatus.clean
  var selectedChange: ChangeSelection? {
    didSet { if tab == .changes, selectedChange != oldValue { showSelectedDiff() } }
  }

  // MARK: History tab

  internal(set) var commits: [Commit] = []
  internal(set) var hasMoreCommits = false
  var selectedCommitID: String? {
    didSet { if tab == .history, selectedCommitID != oldValue { showSelectedDiff() } }
  }

  // MARK: Diff on screen

  internal(set) var diff: Diff? {
    didSet { rebuildRows() }
  }
  internal(set) var diffError: String?
  internal(set) var isLoadingDiff = false
  internal(set) var collapsedFiles: Set<Int> = [] {
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

  /// The current diff, flattened for the table. Rebuilt only when the diff,
  /// layout, or collapsed files change, never while scrolling.
  private(set) var rows: [DiffRow] = []
  /// Bumped with every rebuild, so the table can tell new rows from old
  /// without comparing them.
  private(set) var rowsVersion = 0
  private(set) var lineNumberDigits = 3
  /// Hands keyboard jumps straight to the table, skipping a SwiftUI update.
  @ObservationIgnored let diffScroller = DiffScroller()

  // MARK: Internal state for the extensions

  @ObservationIgnored var repository: GitRepository?
  @ObservationIgnored var access = RepositoryAccess()
  @ObservationIgnored var watcher: RepositoryWatcher?
  @ObservationIgnored var isLoadingMore = false
  @ObservationIgnored var diffTask: Task<Void, Never>?
  @ObservationIgnored var prefetchTask: Task<Void, Never>?
  @ObservationIgnored var statusTask: Task<Void, Never>?
  @ObservationIgnored var statusRefreshQueued = false
  @ObservationIgnored var cache = DiffCache(capacity: 32)
  @ObservationIgnored var diffRequestedAt: ContinuousClock.Instant?
  /// The reader's position in the diff: the top-most visible row, or the last
  /// place a keyboard jump landed. Not observed: it changes on every scroll.
  @ObservationIgnored var cursor = DiffRowID.top

  nonisolated static let firstPageSize = 100
  static let pageSize = 200
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
  struct Opened: Sendable {
    let repository: GitRepository
    let info: RepositoryInfo
    let status: WorkingTreeStatus
    let commits: [Commit]
    let firstChange: ChangeSelection?
    let firstDiff: Diff?
  }

  @concurrent
  nonisolated static func load(_ url: URL) async throws -> Opened {
    let repository = try await GitRepository.open(at: url)
    let info = await repository.info()
    let status = try await repository.status()
    let commits = try await repository.firstCommits(limit: firstPageSize)
    let firstChange = ChangeSelection.first(in: status)
    var firstDiff: Diff?
    if let firstChange {
      firstDiff = try? await repository.workingTreeDiff(staged: firstChange.staged, path: firstChange.path)
    }
    return Opened(
      repository: repository, info: info, status: status, commits: commits,
      firstChange: firstChange, firstDiff: firstDiff)
  }

  /// The last repository, already opening. Started from `AditApp.init` so git
  /// work overlaps window creation instead of waiting for the window to appear.
  private static var prewarmed: (access: RepositoryAccess, url: URL, load: Task<Opened, Error>)?

  static func prewarm() {
    let access = RepositoryAccess()
    // `-AditRepository <path>` opens a specific repository, for benchmarks.
    let override = UserDefaults.standard.string(forKey: "AditRepository").map {
      URL(fileURLWithPath: $0)
    }
    guard let url = override ?? access.restore() else { return }
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
        access.adopt(opened.repository.url)
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
    statusTask?.cancel()
    repository = opened.repository
    info = opened.info
    status = opened.status
    commits = opened.commits
    hasMoreCommits = opened.commits.count == Self.firstPageSize
    cache = DiffCache(capacity: 32)
    diffError = nil
    phase = .ready
    watcher = RepositoryWatcher(url: opened.repository.url) { [weak self] change in
      if change.head { self?.refreshHistory() }
      if change.workingTree { self?.refreshWorkingTree(changedAt: change.firstEventAt) }
    }

    // Show the preloaded diff directly, so it paints with the window.
    tab = .changes
    selectedChange = opened.firstChange
    selectedCommitID = opened.commits.first?.id
    diffTask?.cancel()
    diff = opened.firstDiff
    isLoadingDiff = false
    // The first diff paints with the window; the launch budget covers it.
    diffRequestedAt = nil
    if Self.isBenchmarking { Task { await runBenchmark() } }
  }

  /// Rereads everything that can change behind Adit's back: HEAD, history,
  /// and the working tree. Cheap enough to run whenever the app comes forward.
  func refresh() {
    guard phase == .ready else { return }
    refreshHistory()
    refreshWorkingTree()
  }

  // MARK: - Diff loading

  /// The diff the selected tab wants on screen.
  var selectedSource: DiffSource? {
    switch tab {
    case .changes: selectedChange?.source
    case .history: selectedCommitID.map(DiffSource.commit)
    }
  }

  /// Loads the selected tab's diff. With `inPlace`, the same source is being
  /// reloaded (the file changed on disk): keep scroll position and collapsed
  /// files instead of starting over at the top.
  func showSelectedDiff(inPlace: Bool = false) {
    diffTask?.cancel()
    let source = selectedSource
    if !inPlace {
      cursor = .top
      if !collapsedFiles.isEmpty { collapsedFiles = [] }
      diffRequestedAt = .now
    }
    diffError = nil
    guard let source, let repository else {
      diff = nil
      isLoadingDiff = false
      return
    }
    if case .commit(let id) = source, let cached = cache[id] {
      diff = cached
      isLoadingDiff = false
      prefetch(after: id)
      return
    }
    // Keep the previous diff on screen until the new one is ready. Most loads
    // finish inside a frame or two, and a blank flash reads as slower.
    isLoadingDiff = true
    diffTask = Task {
      do {
        let loaded: Diff
        switch source {
        case .commit(let id):
          loaded = try await repository.diff(commitID: id)
          cache[id] = loaded
        case .workingTree(let staged, let path):
          loaded = try await repository.workingTreeDiff(staged: staged, path: path)
        }
        guard !Task.isCancelled, selectedSource == source else { return }
        diff = loaded
        isLoadingDiff = false
        if case .commit(let id) = source { prefetch(after: id) }
      } catch is CancellationError {
      } catch {
        guard selectedSource == source else { return }
        diff = nil
        diffError = "\(error)"
        isLoadingDiff = false
      }
    }
  }

  /// Called by the diff view once the selected diff is on screen.
  func diffDidAppear(_ source: DiffSource) {
    guard let start = diffRequestedAt, source == diff?.source else { return }
    diffRequestedAt = nil
    let lines = diff?.files.reduce(0) { $0 + $1.additions + $1.deletions } ?? 0
    if lines > 10_000 {
      Timing.report("select to diff painted (large diff)", since: start, budget: 100)
    } else {
      Timing.report("select to diff painted", since: start, budget: 50)
    }
  }

  /// Moves the selection in whichever tab is showing.
  func selectNextItem() {
    switch tab {
    case .changes: moveChangeSelection(by: 1)
    case .history: moveCommitSelection(by: 1)
    }
  }

  func selectPreviousItem() {
    switch tab {
    case .changes: moveChangeSelection(by: -1)
    case .history: moveCommitSelection(by: -1)
    }
  }
}

/// Which working-tree diff the Changes tab has selected: one file, or every
/// file in a group when `path` is nil.
struct ChangeSelection: Hashable, Sendable {
  let staged: Bool
  let path: String?

  var source: DiffSource { .workingTree(staged: staged, path: path) }

  /// Where the Changes tab starts: the first unstaged file, since that's what
  /// you review next, else the first staged one.
  static func first(in status: WorkingTreeStatus) -> ChangeSelection? {
    if let file = status.unstaged.first { return ChangeSelection(staged: false, path: file.path) }
    if let file = status.staged.first { return ChangeSelection(staged: true, path: file.path) }
    return nil
  }
}

/// Recently built commit diffs, so moving back and forth through history is
/// instant. Commits are immutable, so an entry never goes stale.
struct DiffCache {
  let capacity: Int
  private var entries: [String: Diff] = [:]
  private var order: [String] = []

  init(capacity: Int) { self.capacity = capacity }

  subscript(id: String) -> Diff? {
    get { entries[id] }
    set {
      guard let newValue else { return }
      if entries.updateValue(newValue, forKey: id) == nil { order.append(id) }
      if order.count > capacity { entries[order.removeFirst()] = nil }
    }
  }
}
