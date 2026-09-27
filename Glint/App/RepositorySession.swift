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
  /// Set when the opened folder holds several repositories; `repository` is
  /// then the active one.
  internal(set) var workspace: Workspace?
  /// Branch and changes for every repository in the workspace, keyed by
  /// relative path, for the repository picker.
  internal(set) var repositorySummaries: [String: RepositorySummary] = [:]
  var isRepositoryPickerShown = false
  var isProjectSwitcherShown = false
  /// This window's terminal tabs, per repository, alive while hidden.
  @ObservationIgnored let terminals = TerminalStore()

  /// The terminal panel under the diff. Remembered between launches.
  var isTerminalShown = UserDefaults.standard.bool(forKey: "terminalShown") {
    didSet { UserDefaults.standard.set(isTerminalShown, forKey: "terminalShown") }
  }
  /// Lists the other repositories' changes under the active one's.
  var showsAllRepositories = UserDefaults.standard.bool(forKey: "showsAllRepositories") {
    didSet { UserDefaults.standard.set(showsAllRepositories, forKey: "showsAllRepositories") }
  }
  /// Shown as an alert: failures of actions the user asked for.
  var alert: UserAlert?
  /// What Try Again in the current alert runs, if it has one.
  @ObservationIgnored var retryAlertAction: (() -> Void)?
  /// Files waiting for the user to confirm a discard.
  var pendingDiscard: [ChangedFile]?

  // MARK: Commit box

  var commitMessage = "" {
    didSet { if commitMessage != oldValue { scheduleDraftSave() } }
  }
  var isAmending = false {
    didSet { if isAmending, !oldValue { prefillAmendMessage() } }
  }
  internal(set) var isCommitting = false
  /// Size of what Commit would take right now, shown in the commit box.
  internal(set) var commitSize: ChangeSize?
  /// The last message AI wrote, to measure how much you edit it before
  /// committing. Logged locally, never sent.
  @ObservationIgnored var generatedMessage: String?
  /// Which model wrote the last AI message, shown under the commit box.
  internal(set) var aiNote: String?
  /// Writing a message with AI. Observed so the button can show Stop.
  internal(set) var messageTask: Task<Void, Never>?
  /// Bumped to move keyboard focus into the commit message.
  /// Focus to give the message box, or take from it, next time the commit
  /// panel is on screen. The panel clears it once done, so a request made
  /// while switching to Changes isn't lost.
  var messageFocusRequest: Bool?

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
  /// The branch this one is compared with in the pinned branch-diff row, or
  /// nil when there's none (no main or master, or on main itself).
  internal(set) var branchBaseName: String?
  /// The branch diff's comparison, once loaded.
  internal(set) var branchComparison: BranchComparison?
  /// History's pinned first row. Commit ids are 40 hex characters, so this
  /// can't collide with one.
  static let branchSelectionID = "branch-diff"
  internal(set) var hasMoreCommits = false
  var selectedCommitID: String? {
    didSet { if tab == .history, selectedCommitID != oldValue { showSelectedDiff() } }
  }

  // MARK: Diff on screen

  internal(set) var diff: Diff? {
    didSet { rebuildRows(.all) }
  }
  internal(set) var diffError: String?
  internal(set) var isLoadingDiff = false
  internal(set) var collapsedFiles: Set<Int> = [] {
    // Set.remove of a missing member still counts as a set. Without this check
    // every hunk jump rebuilt every row and reloaded the whole table.
    didSet {
      guard collapsedFiles != oldValue, !suppressRowsRebuild else { return }
      let changed = collapsedFiles.symmetricDifference(oldValue)
      rebuildRows(changed.count == 1 ? .file(changed.first!) : .all)
    }
  }

  /// Unified or split. Remembered between launches.
  var layout: DiffLayout {
    didSet {
      guard layout != oldValue else { return }
      UserDefaults.standard.set(layout.rawValue, forKey: Self.layoutKey)
      rebuildRows(.all)
    }
  }

  /// The current diff, flattened for the table. Rebuilt only when the diff,
  /// layout, or collapsed files change, never while scrolling.
  private(set) var rows: [DiffRow] = []
  /// Bumped with every rebuild, so the table can tell new rows from old
  /// without comparing them.
  private(set) var rowsVersion = 0
  /// What the last rebuild changed, so the table can update just those rows.
  private(set) var rowsChange = RowsChange.all

  enum RowsChange: Equatable {
    case all
    /// One file collapsed or expanded; every other row is unchanged.
    case file(Int)
  }
  private(set) var lineNumberDigits = 3
  // MARK: Branches

  internal(set) var branches: [Branch] = []
  var isBranchPickerShown = false {
    didSet { if isBranchPickerShown, !oldValue { loadBranches() } }
  }
  internal(set) var isSwitchingBranch = false

  // MARK: Remotes

  enum NetworkOperation: String {
    case fetch = "Fetching", pull = "Pulling", push = "Pushing"

    var verb: String {
      switch self {
      case .fetch: "fetch"
      case .pull: "pull"
      case .push: "push"
      }
    }
  }

  internal(set) var sync = SyncStatus.none
  internal(set) var networkOperation: NetworkOperation?
  /// How the last fetch, pull, or push went, shown on the sync button for a
  /// moment afterwards.
  internal(set) var syncOutcome: SyncOutcome?
  /// True for a moment after a commit, so the last-commit row can say so.
  internal(set) var justCommitted = false

  enum SyncOutcome: Equatable {
    case fetched, pulled(Int), pushed(Int)
  }

  /// Changed lines selected in a working-tree diff, for line staging.
  internal(set) var selectedLineRows: [DiffRowID] = []
  /// Hands keyboard jumps straight to the table, skipping a SwiftUI update.
  @ObservationIgnored let diffScroller = DiffScroller()

  // MARK: Internal state for the extensions

  @ObservationIgnored var repository: GitRepository?
  @ObservationIgnored var access = RepositoryAccess()
  @ObservationIgnored var watcher: RepositoryWatcher?
  /// Unsent commit messages per repository, kept while you switch between
  /// the repositories of a workspace.
  @ObservationIgnored var messageDrafts: [URL: String] = [:]
  @ObservationIgnored private var draftSave: Task<Void, Never>?
  /// The folder being opened, for the "Opening…" screen.
  internal(set) var openingName: String?

  private static let draftsKey = "messageDrafts"

  /// A message you were writing, from last time. Kept per repository, so a
  /// quit or crash doesn't lose it.
  static func savedDraft(for repository: URL) -> String {
    (UserDefaults.standard.dictionary(forKey: draftsKey) as? [String: String])?[repository.standardizedFileURL.path] ?? ""
  }

  /// Saves the draft half a second after you stop typing.
  private func scheduleDraftSave() {
    draftSave?.cancel()
    guard let repository = repository?.url else { return }
    let message = commitMessage
    draftSave = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      var drafts = UserDefaults.standard.dictionary(forKey: Self.draftsKey) as? [String: String] ?? [:]
      let key = repository.standardizedFileURL.path
      drafts[key] = message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : message
      UserDefaults.standard.set(drafts, forKey: Self.draftsKey)
    }
  }
  /// Open handles for the workspace's other repositories, used to keep their
  /// summaries current without switching to them.
  @ObservationIgnored var summaryHandles: [String: GitRepository] = [:]
  @ObservationIgnored var summaryTask: Task<Void, Never>?
  @ObservationIgnored var isLoadingMore = false
  @ObservationIgnored var diffTask: Task<Void, Never>?
  @ObservationIgnored var rowsTask: Task<Void, Never>?
  @ObservationIgnored var suppressRowsRebuild = false
  @ObservationIgnored var prefetchTask: Task<Void, Never>?
  @ObservationIgnored var statusTask: Task<Void, Never>?
  @ObservationIgnored var statusRefreshQueued = false
  /// Files waiting for a partial status; nil when a full one is queued.
  @ObservationIgnored var pendingStatusPaths: Set<String>?
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

  private func rebuildRows(_ change: RowsChange) {
    rowsTask?.cancel()
    guard let diff else {
      rowsChange = change
      rowsVersion += 1
      rows = []
      return
    }
    let lineCount = diff.files.reduce(0) { $0 + $1.additions + $1.deletions }
    guard lineCount > Self.backgroundRowsThreshold else {
      rowsChange = change
      rowsVersion += 1
      rows = DiffRow.build(diff, layout: layout, collapsed: collapsedFiles)
      lineNumberDigits = DiffRow.lineNumberDigits(diff)
      return
    }
    // A very large diff (a vendored library, a lockfile rewrite) takes tens of
    // milliseconds to flatten; do it off the main thread and keep showing the
    // previous rows meanwhile.
    let layout = self.layout
    let collapsed = collapsedFiles
    rowsTask = Task {
      let built = await Task.detached(priority: .userInitiated) {
        (DiffRow.build(diff, layout: layout, collapsed: collapsed), DiffRow.lineNumberDigits(diff))
      }.value
      guard !Task.isCancelled, self.diff?.source == diff.source, self.layout == layout,
        self.collapsedFiles == collapsed
      else { return }
      rowsChange = change
      rowsVersion += 1
      rows = built.0
      lineNumberDigits = built.1
    }
  }

  /// Diffs past this many changed lines get their rows built in the
  /// background.
  private static let backgroundRowsThreshold = 20_000
  /// Past this many changed lines, only the first screen's files open
  /// expanded; the rest show as headers you can expand. Sizing 200,000 rows
  /// blocked the main thread for over a second.
  static let collapseThreshold = 50_000

  /// Shows a complete diff. A huge one arriving fresh (not a live reload of
  /// the same one) opens with files past the first screen collapsed.
  func showComplete(_ complete: Diff, fresh: Bool) {
    let total = complete.files.reduce(0) { $0 + $1.additions + $1.deletions }
    if fresh, total > Self.collapseThreshold {
      let visible = complete.firstScreen(lines: 5_000).files.count
      suppressRowsRebuild = true
      collapsedFiles = Set(visible..<complete.files.count)
      suppressRowsRebuild = false
    }
    diff = complete
  }

  // MARK: - Opening

  /// Everything the first frame needs, loaded in one go off the main actor.
  struct Opened: Sendable {
    let workspace: Workspace?
    let repository: GitRepository
    let info: RepositoryInfo
    let status: WorkingTreeStatus
    let sync: SyncStatus
    let branchBase: String?
    let commits: [Commit]
    let firstChange: ChangeSelection?
    let firstDiff: Diff?
  }

  /// Opens the repository containing `url`. A folder that isn't inside one
  /// but holds several opens as a workspace, on the repository used last.
  /// `workspace` is passed when switching within one that's already open.
  @concurrent
  nonisolated static func load(_ url: URL, in known: Workspace? = nil) async throws -> Opened {
    var workspace = known
    let repository: GitRepository
    do {
      repository = try await GitRepository.open(at: url)
    } catch let error as GitError where error.isNotARepository && known == nil {
      let searchStart = ContinuousClock.now
      let found = RepositoryDiscovery.repositories(in: url)
      Timing.report("find repositories", since: searchStart, budget: 50)
      guard !found.isEmpty else {
        throw GitError(
          code: error.code,
          message: "\(url.lastPathComponent) isn't a git repository, and there are none inside it.")
      }
      let root = url.standardizedFileURL
      let last = WorkspaceMemory.activeRepository(in: root)
      let active = found.first { $0.relativePath == last } ?? found[0]
      workspace = Workspace(root: root, repositories: found)
      repository = try await GitRepository.open(at: active.url)
    }
    // Each stage is timed: opening is the launch budget's biggest share.
    var mark = ContinuousClock.now
    func stage(_ name: StaticString) {
      Timing.report(name, since: mark, budget: 50)
      mark = .now
    }
    let info = await repository.info()
    stage("open: info")
    let status = try await repository.status()
    stage("open: status")
    let sync = await repository.syncStatus()
    stage("open: ahead and behind")
    let commits = try await repository.firstCommits(limit: firstPageSize)
    stage("open: first commits")
    let branchBase = await repository.branchBase()?.name
    let firstChange = ChangeSelection.first(in: status)
    var firstDiff: Diff?
    if let firstChange {
      firstDiff = try? await repository.workingTreeDiff(staged: firstChange.staged, path: firstChange.path)
    }
    stage("open: first diff")
    return Opened(
      workspace: workspace, repository: repository, info: info, status: status, sync: sync,
      branchBase: branchBase, commits: commits,
      firstChange: firstChange, firstDiff: firstDiff)
  }

  /// The last repository, already opening. Started from `GlintApp.init` so git
  /// work overlaps window creation instead of waiting for the window to appear.
  private static var prewarmed: (access: RepositoryAccess, url: URL, load: Task<Opened, Error>)?

  static func prewarm() {
    _ = LoginEnvironment.shared
    let access = RepositoryAccess()
    // `-GlintRepository <path>` opens a specific repository, for benchmarks.
    let override = UserDefaults.standard.string(forKey: "GlintRepository").map {
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
    openProject(url)
  }

  /// The open project: the folder of repositories, or the repository.
  var projectURL: URL? { workspace?.root ?? repositoryURL }

  /// Opens a project from the title's switcher.
  func openProject(_ url: URL) {
    isProjectSwitcherShown = false
    guard projectURL.map({ !Self.sameFolder($0, url) }) ?? true else { return }
    open(url, restoring: false, loading: Task { try await Self.load(url) })
  }

  /// Your recent projects, newest first, for the switcher.
  func recentProjects() -> [URL] { access.recents() }

  private static func sameFolder(_ a: URL, _ b: URL) -> Bool {
    a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
  }

  private func open(_ url: URL, restoring: Bool, loading: Task<Opened, Error>) {
    openingName = url.lastPathComponent
    if repository == nil { phase = .opening }
    Task {
      do {
        let opened = try await loading.value
        // A repository opened with -GlintRepository (benchmarks, tests) isn't
        // one you picked, so it doesn't replace the one Glint reopens.
        if UserDefaults.standard.string(forKey: "GlintRepository") == nil {
          access.adopt(opened.workspace?.root ?? opened.repository.url)
        }
        install(opened)
      } catch {
        let message = "\(url.lastPathComponent): \(error)"
        if restoring {
          access.forget(url)
          phase = .closed(message: "Couldn't reopen \(message)")
        } else if repository == nil {
          phase = .closed(message: "Couldn't open \(message)")
        } else {
          alert = UserAlert("Couldn't open \(url.lastPathComponent)", error: error)
        }
      }
    }
  }

  func install(_ opened: Opened, selecting preferred: ChangeSelection? = nil) {
    diffTask?.cancel()
    prefetchTask?.cancel()
    statusTask?.cancel()
    messageTask?.cancel()
    messageTask = nil
    if let current = repository?.url { messageDrafts[current] = commitMessage }
    let keepsHistory = tab == .history && repository != nil
    isAmending = false
    workspace = opened.workspace
    if let workspace, let active = workspace.repositories.first(where: { $0.url.standardizedFileURL == opened.repository.url.standardizedFileURL }) {
      WorkspaceMemory.remember(active.relativePath, in: workspace.root)
    }
    repository = opened.repository
    // After `repository` changes, so the draft saves under the right one.
    commitMessage = messageDrafts[opened.repository.url] ?? Self.savedDraft(for: opened.repository.url)
    info = opened.info
    status = opened.status
    refreshCommitSize()
    commits = opened.commits
    sync = opened.sync
    branchBaseName = opened.branchBase
    branchComparison = nil
    hasMoreCommits = opened.commits.count == Self.firstPageSize
    cache = DiffCache(capacity: 32)
    diffError = nil
    phase = .ready
    // A workspace is watched once, from its folder; events are routed to the
    // repository they belong to.
    if watcher == nil || watcher?.root != (opened.workspace?.root ?? opened.repository.url).standardizedFileURL.path {
      watcher = RepositoryWatcher(url: opened.workspace?.root ?? opened.repository.url) { [weak self] change in
        self?.filesChanged(change)
      }
    }

    // Show the preloaded diff directly, so it paints with the window.
    // Switching repository from History stays in History.
    tab = .changes
    defer {
      if keepsHistory {
        tab = .history
        showSelectedDiff()
      }
    }
    selectedChange = opened.firstChange
    selectedCommitID = opened.commits.first?.id
    diffTask?.cancel()
    diff = opened.firstDiff
    isLoadingDiff = false
    // The first diff paints with the window; the launch budget covers it.
    diffRequestedAt = nil
    // Switching repositories from a file in the all-repositories list lands
    // on that file.
    if let preferred, preferred != selectedChange,
      (preferred.staged ? status.staged : status.unstaged).contains(where: { $0.path == preferred.path })
    {
      selectedChange = preferred
    }
    if workspace != nil {
      updateActiveSummary()
      refreshSummaries(of: nil)
    }
    if Self.isBenchmarking { Task { await runBenchmark() } }
    if Self.isTestingAI { Task { await runAITest() } }
  }

  /// Rereads everything that can change behind Glint's back: HEAD, history,
  /// and the working tree. Cheap enough to run whenever the app comes forward.
  func refresh() {
    guard phase == .ready else { return }
    refreshHistory()
    refreshWorkingTree()
    if workspace != nil { refreshSummaries(of: nil) }
  }

  // MARK: - Diff loading

  /// The diff the selected tab wants on screen.
  var selectedSource: DiffSource? {
    switch tab {
    case .changes: selectedChange?.source
    case .history:
      selectedCommitID == Self.branchSelectionID ? .branch : selectedCommitID.map(DiffSource.commit)
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
      let first = cached.firstScreen(lines: 5_000)
      diff = first
      isLoadingDiff = !first.isComplete
      if !first.isComplete {
        // A huge cached diff: paint its first screen now, the rest next.
        diffTask = Task {
          await Task.yield()
          guard !Task.isCancelled, selectedSource == source else { return }
          showComplete(cached, fresh: true)
          isLoadingDiff = false
        }
      }
      prefetch(after: id)
      return
    }
    // Keep the previous diff on screen until the new one is ready. Most loads
    // finish inside a frame or two, and a blank flash reads as slower. A
    // reload in place (after staging, after a save) shows no spinner at all.
    if !inPlace { isLoadingDiff = true }
    diffTask = Task {
      do {
        // Big commits and branches show their first screenful first; the
        // rest follows in place.
        let firstScreen = 5_000
        var loaded: Diff
        switch source {
        case .commit(let id):
          loaded = try await repository.diff(commitID: id, lineBudget: firstScreen)
        case .workingTree(let staged, let path):
          loaded = try await repository.workingTreeDiff(staged: staged, path: path)
        case .branch:
          let (branchDiff, comparison) = try await repository.branchDiff(lineBudget: firstScreen)
          loaded = branchDiff
          branchComparison = comparison
        }
        guard !Task.isCancelled, selectedSource == source else { return }
        diff = loaded
        if !loaded.isComplete {
          switch source {
          case .commit(let id): loaded = try await repository.diff(commitID: id)
          case .branch: loaded = try await repository.branchDiff().0
          case .workingTree: break
          }
          guard !Task.isCancelled, selectedSource == source else { return }
          showComplete(loaded, fresh: !inPlace)
        }
        if case .commit(let id) = source { cache[id] = loaded }
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
    let ms = Timing.milliseconds(since: start)
    let budget: Double = lines > 10_000 ? 100 : 50
    Timing.log.info(
      "select to diff painted: \(ms, format: .fixed(precision: 1)) ms (\(lines) lines, \(self.rows.count) rows, budget \(budget, format: .fixed(precision: 0)) ms, \(ms <= budget ? "ok" : "OVER BUDGET", privacy: .public))")
  }

  /// Single-key commands from `KeyMonitor`. Returns false for keys it doesn't
  /// use, so they reach the focused control as usual.
  func handleKey(_ key: Character) -> Bool {
    guard phase == .ready, let command = ShortcutStore.shared.singleKeyCommand(for: key) else { return false }
    switch command {
    case .nextItem: selectNextItem()
    case .previousItem: selectPreviousItem()
    case .nextHunk: nextHunk()
    case .previousHunk: previousHunk()
    case .toggleCollapsed: toggleCurrentFileCollapsed()
    case .toggleStaged:
      guard tab == .changes else { return false }
      toggleSelectedStaged()
    case .focusCommitMessage:
      tab = .changes
      messageFocusRequest = true
    case .stagePartial:
      guard isPartialStagingAvailable else { return false }
      stageAtCursor()
    default:
      return false
    }
    return true
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
