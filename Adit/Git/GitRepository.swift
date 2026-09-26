internal import Clibgit2
import Foundation

/// One open repository. libgit2 handles are not thread-safe, so every handle
/// lives inside this actor and nothing libgit2-shaped leaves it: callers get
/// `Sendable` value types from `Models/`.
actor GitRepository {
  nonisolated let url: URL
  // Only touched from actor-isolated methods, plus `deinit`, which runs once
  // no other reference exists. `nonisolated(unsafe)` is for the deinit alone.
  nonisolated(unsafe) private let handle: OpaquePointer
  /// The commit list's walk, kept alive between pages.
  nonisolated(unsafe) private var walk: OpaquePointer?

  private init(url: URL, handle: OpaquePointer) {
    self.url = url
    self.handle = handle
  }

  deinit {
    if let walk { git_revwalk_free(walk) }
    git_repository_free(handle)
  }

  /// Opens the repository containing `url`. Picking a subfolder of a
  /// repository opens the repository itself, like `git` in a terminal.
  @concurrent
  static func open(at url: URL) async throws -> GitRepository {
    _ = LibGit2.initialized
    var repo: OpaquePointer?
    let code = url.withUnsafeFileSystemRepresentation { path in
      git_repository_open_ext(&repo, path, 0, nil)
    }
    if code == GIT_ENOTFOUND.rawValue {
      throw GitError(
        code: code,
        message: "\(url.lastPathComponent) isn't inside a git repository.")
    }
    try GitError.check(code, "Couldn't open \(url.path).")
    guard let workdir = git_repository_workdir(repo) else {
      git_repository_free(repo)
      throw GitError(code: -1, message: "\(url.lastPathComponent) is a bare repository, with no files to show.")
    }
    let root = URL(fileURLWithPath: String(cString: workdir), isDirectory: true)
    return GitRepository(url: root.standardizedFileURL, handle: repo!)
  }

  // MARK: - Repository

  func info() -> RepositoryInfo {
    let isEmpty = git_repository_head_unborn(handle) == 1
    var branch: String?
    var head: OpaquePointer?
    if git_reference_lookup(&head, handle, "HEAD") == 0, let head {
      if let target = git_reference_symbolic_target(head) {
        branch = String(cString: target).replacingOccurrences(
          of: "refs/heads/", with: "", options: .anchored)
      }
      git_reference_free(head)
    }
    return RepositoryInfo(url: url, branch: branch, isEmpty: isEmpty)
  }

  /// The commit HEAD points at, or nil for an empty repository.
  func headCommitID() -> String? {
    var oid = git_oid()
    guard git_reference_name_to_id(&oid, handle, "HEAD") == 0 else { return nil }
    return Self.hex(oid)
  }

  // MARK: - Working tree

  /// Staged and unstaged changes, like `git status`. Untracked folders are
  /// listed file by file; ignored files and submodules are left out.
  /// With `paths`, checks just those files (exact paths, no globbing): what
  /// the file watcher saw change. Much cheaper than a full scan on a large
  /// repository; merge it in with `WorkingTreeStatus.merging`.
  func status(paths: [String]? = nil) throws -> WorkingTreeStatus {
    try reloadIndex()
    var options = git_status_options()
    git_status_options_init(&options, UInt32(GIT_STATUS_OPTIONS_VERSION))
    options.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
    options.flags =
      GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue
      | GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue
      | GIT_STATUS_OPT_EXCLUDE_SUBMODULES.rawValue

    let pathspec = paths.map(CStringArray.init)
    if let pathspec {
      options.pathspec = pathspec.array
      options.flags |= GIT_STATUS_OPT_DISABLE_PATHSPEC_MATCH.rawValue
    }
    var list: OpaquePointer?
    try GitError.check(git_status_list_new(&list, handle, &options), "Couldn't read changes.")
    withExtendedLifetime(pathspec) {}
    defer { git_status_list_free(list) }

    var result = WorkingTreeStatus.clean
    for index in 0..<git_status_list_entrycount(list) {
      guard let entry = git_status_byindex(list, index)?.pointee else { continue }
      let flags = entry.status.rawValue
      let delta = entry.index_to_workdir ?? entry.head_to_index
      guard let delta, let cPath = delta.pointee.new_file.path ?? delta.pointee.old_file.path
      else { continue }
      let path = String(cString: cPath)

      if flags & GIT_STATUS_CONFLICTED.rawValue != 0 {
        result.unstaged.append(ChangedFile(path: path, kind: .conflicted))
        continue
      }
      if let kind = Self.stagedKind(flags) {
        result.staged.append(ChangedFile(path: path, kind: kind))
      }
      if let kind = Self.unstagedKind(flags) {
        result.unstaged.append(ChangedFile(path: path, kind: kind))
      }
    }
    let order = FileOrder.current
    result.staged = order.sorted(result.staged, path: \.path)
    result.unstaged = order.sorted(result.unstaged, path: \.path)
    return result
  }

  // MARK: - Staging

  /// Stages whole files, like `git add`. A path that no longer exists on disk
  /// is staged as a deletion.
  func stage(_ paths: [String]) throws {
    try withIndex { index in
      for path in paths {
        let exists = (try? FileManager.default.attributesOfItem(atPath: url.appendingPathComponent(path).path)) != nil
        let code = exists ? git_index_add_bypath(index, path) : git_index_remove_bypath(index, path)
        try GitError.check(code, "Couldn't stage \(path).")
      }
    }
  }

  /// Stages every change, new and deleted files included, like `git add -A`.
  func stageAll() throws {
    try withIndex { index in
      try GitError.check(
        git_index_add_all(index, nil, GIT_INDEX_ADD_DEFAULT.rawValue, nil, nil), "Couldn't stage everything.")
      try GitError.check(git_index_update_all(index, nil, nil, nil), "Couldn't stage deletions.")
    }
  }

  /// Unstages files, keeping their changes in the working tree, like
  /// `git restore --staged`.
  func unstage(_ paths: [String]) throws {
    guard !paths.isEmpty else { return }
    try reloadIndex()
    var head: OpaquePointer?
    if git_repository_head_unborn(handle) != 1 {
      try GitError.check(git_revparse_single(&head, handle, "HEAD"), "Couldn't read HEAD.")
    }
    defer { if let head { git_object_free(head) } }
    let strings = CStringArray(paths)
    var array = strings.array
    // With no HEAD, resetting to nothing removes the entries from the index.
    for attempt in 0..<5 {
      let code = git_reset_default(handle, head, &array)
      if code != GIT_ELOCKED.rawValue || attempt == 4 {
        try GitError.check(code, "Couldn't unstage.")
        return
      }
      usleep(20_000)
    }
  }

  /// Applies a patch to the index only, leaving the working tree alone. This
  /// is how hunk and line staging work: see `Patch`.
  func applyToIndex(_ patch: String) throws {
    try reloadIndex()
    var diff: OpaquePointer?
    try GitError.check(
      git_diff_from_buffer(&diff, patch, patch.utf8.count), "Couldn't read the patch for those lines.")
    defer { git_diff_free(diff) }
    var options = git_apply_options()
    git_apply_options_init(&options, UInt32(GIT_APPLY_OPTIONS_VERSION))
    try GitError.check(
      git_apply(handle, diff, GIT_APPLY_LOCATION_INDEX, &options),
      "Those lines no longer match what's staged. The diff was out of date; try again.")
  }

  /// Throws away unstaged changes to tracked files by restoring them from the
  /// index, like `git restore`. Staged changes are kept. Untracked files
  /// aren't touched here: the caller moves those to the Trash.
  func discard(_ paths: [String]) throws {
    guard !paths.isEmpty else { return }
    try reloadIndex()
    let strings = CStringArray(paths)
    var options = git_checkout_options()
    git_checkout_options_init(&options, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
    options.checkout_strategy = GIT_CHECKOUT_FORCE.rawValue | GIT_CHECKOUT_DISABLE_PATHSPEC_MATCH.rawValue
    options.paths = strings.array
    try GitError.check(git_checkout_index(handle, nil, &options), "Couldn't discard changes.")
  }

  /// Runs `body` on the freshly read index, then writes it back. Another git
  /// process holding `index.lock` gets a few quick retries before giving up.
  private func withIndex(_ body: (OpaquePointer) throws -> Void) throws {
    var index: OpaquePointer?
    try GitError.check(git_repository_index(&index, handle), "Couldn't read the index.")
    defer { git_index_free(index) }
    try GitError.check(git_index_read(index, 0), "Couldn't read the index.")
    try body(index!)
    try retryingLock("Couldn't save the index.") { git_index_write(index) }
  }

  private func retryingLock(_ message: String, _ attempt: () -> Int32) throws {
    for _ in 0..<5 {
      let code = attempt()
      if code != GIT_ELOCKED.rawValue { return try GitError.check(code, message) }
      usleep(20_000)
    }
    throw GitError(
      code: GIT_ELOCKED.rawValue,
      message: "Another git process is using this repository (.git/index.lock). Try again in a moment. If it keeps happening and nothing else is running git, delete that file.")
  }

  /// libgit2 caches the index. Other tools (the terminal, the editor) write it
  /// too, so reread it from disk if it changed before trusting it.
  private func reloadIndex() throws {
    var index: OpaquePointer?
    try GitError.check(git_repository_index(&index, handle), "Couldn't read the index.")
    defer { git_index_free(index) }
    try GitError.check(git_index_read(index, 0), "Couldn't read the index.")
  }

  private static func stagedKind(_ flags: UInt32) -> ChangedFile.Kind? {
    if flags & GIT_STATUS_INDEX_NEW.rawValue != 0 { return .added }
    if flags & GIT_STATUS_INDEX_DELETED.rawValue != 0 { return .deleted }
    if flags & GIT_STATUS_INDEX_RENAMED.rawValue != 0 { return .renamed }
    if flags & GIT_STATUS_INDEX_TYPECHANGE.rawValue != 0 { return .typeChanged }
    if flags & GIT_STATUS_INDEX_MODIFIED.rawValue != 0 { return .modified }
    return nil
  }

  private static func unstagedKind(_ flags: UInt32) -> ChangedFile.Kind? {
    if flags & GIT_STATUS_WT_NEW.rawValue != 0 { return .untracked }
    if flags & GIT_STATUS_WT_DELETED.rawValue != 0 { return .deleted }
    if flags & GIT_STATUS_WT_RENAMED.rawValue != 0 { return .renamed }
    if flags & GIT_STATUS_WT_TYPECHANGE.rawValue != 0 { return .typeChanged }
    if flags & GIT_STATUS_WT_MODIFIED.rawValue != 0 { return .modified }
    return nil
  }

  /// The full message of the HEAD commit, for amending.
  func headMessage() -> String? {
    var oid = git_oid()
    guard git_reference_name_to_id(&oid, handle, "HEAD") == 0 else { return nil }
    var commit: OpaquePointer?
    guard git_commit_lookup(&commit, handle, &oid) == 0 else { return nil }
    defer { git_commit_free(commit) }
    return git_commit_message(commit).map { String(cString: $0) }
  }

  /// Moves the branch back one commit and keeps that commit's changes staged,
  /// like `git reset --soft HEAD~1`. Returns the undone commit's message.
  func undoLastCommit() throws -> String {
    var oid = git_oid()
    try GitError.check(git_reference_name_to_id(&oid, handle, "HEAD"), "There's no commit to undo.")
    var commit: OpaquePointer?
    try GitError.check(git_commit_lookup(&commit, handle, &oid), "Couldn't read the last commit.")
    defer { git_commit_free(commit) }
    guard git_commit_parentcount(commit) > 0 else {
      throw GitError(code: -1, message: "That's the repository's first commit, so there's nothing before it to go back to.")
    }
    let message = git_commit_message(commit).map { String(cString: $0) } ?? ""
    var parent: OpaquePointer?
    try GitError.check(git_commit_parent(&parent, commit, 0), "Couldn't read the commit before it.")
    defer { git_commit_free(parent) }
    try GitError.check(git_reset(handle, parent, GIT_RESET_SOFT, nil), "Couldn't undo the commit.")
    return message
  }

  // MARK: - Branches

  /// Local branches, then remote branches that have no local counterpart,
  /// each group newest first. Remote HEAD pointers are left out.
  func branches() throws -> [Branch] {
    var iterator: OpaquePointer?
    try GitError.check(git_branch_iterator_new(&iterator, handle, GIT_BRANCH_ALL), "Couldn't list branches.")
    defer { git_branch_iterator_free(iterator) }

    var local: [Branch] = []
    var remote: [Branch] = []
    var reference: OpaquePointer?
    var type = GIT_BRANCH_LOCAL
    while git_branch_next(&reference, &type, iterator) == 0 {
      defer { git_reference_free(reference) }
      var cName: UnsafePointer<CChar>?
      guard git_branch_name(&cName, reference) == 0, let cName else { continue }
      let name = String(cString: cName)
      if name.hasSuffix("/HEAD") { continue }
      let isRemote = type == GIT_BRANCH_REMOTE
      let branch = Branch(
        name: name, isRemote: isRemote, isCurrent: !isRemote && git_branch_is_head(reference) == 1,
        date: tipDate(reference))
      if isRemote { remote.append(branch) } else { local.append(branch) }
    }
    let localNames = Set(local.map(\.name))
    remote.removeAll { localNames.contains($0.switchName) }
    return local.sorted { $0.date > $1.date } + remote.sorted { $0.date > $1.date }
  }

  /// Ahead and behind counts for the current branch against its upstream.
  func syncStatus() -> SyncStatus {
    var remotes = git_strarray()
    let hasRemotes = git_remote_list(&remotes, handle) == 0 && remotes.count > 0
    git_strarray_dispose(&remotes)

    var head: OpaquePointer?
    guard git_repository_head(&head, handle) == 0, let head else {
      return SyncStatus(upstream: nil, ahead: 0, behind: 0, hasRemotes: hasRemotes)
    }
    defer { git_reference_free(head) }
    var upstream: OpaquePointer?
    guard git_branch_upstream(&upstream, head) == 0, let upstream else {
      return SyncStatus(upstream: nil, ahead: 0, behind: 0, hasRemotes: hasRemotes)
    }
    defer { git_reference_free(upstream) }

    var name: UnsafePointer<CChar>?
    git_branch_name(&name, upstream)
    var ahead = 0
    var behind = 0
    if let local = git_reference_target(head), let remote = git_reference_target(upstream) {
      git_graph_ahead_behind(&ahead, &behind, handle, local, remote)
    }
    return SyncStatus(
      upstream: name.map { String(cString: $0) }, ahead: ahead, behind: behind, hasRemotes: hasRemotes)
  }

  /// The remote to publish a new branch to: `origin` if there is one, else the
  /// only remote. Nil when it's ambiguous or there are none.
  func defaultRemote() -> String? {
    var remotes = git_strarray()
    guard git_remote_list(&remotes, handle) == 0 else { return nil }
    defer { git_strarray_dispose(&remotes) }
    let names = (0..<remotes.count).compactMap { remotes.strings[$0].map { String(cString: $0) } }
    if names.contains("origin") { return "origin" }
    return names.count == 1 ? names[0] : nil
  }

  private func tipDate(_ reference: OpaquePointer?) -> Date {
    guard let target = git_reference_target(reference) else { return .distantPast }
    var commit: OpaquePointer?
    guard git_commit_lookup(&commit, handle, target) == 0 else { return .distantPast }
    defer { git_commit_free(commit) }
    return Date(timeIntervalSince1970: TimeInterval(git_commit_time(commit)))
  }

  // MARK: - Commits

  /// Starts a new walk from HEAD, newest first, and returns the first page.
  func firstCommits(limit: Int) throws -> [Commit] {
    if let walk { git_revwalk_free(walk) }
    walk = nil
    // A fresh repository has a HEAD that names a branch with no commits yet.
    if git_repository_head_unborn(handle) == 1 { return [] }

    var newWalk: OpaquePointer?
    try GitError.check(git_revwalk_new(&newWalk, handle), "Couldn't read history.")
    walk = newWalk
    // Same default order as `git log`: reverse chronological, streamed. A
    // topological sort would force reading the whole history up front.
    git_revwalk_sorting(newWalk, GIT_SORT_NONE.rawValue)

    try GitError.check(git_revwalk_push_head(newWalk), "Couldn't read history.")
    return try moreCommits(limit: limit)
  }

  /// Continues the walk started by `firstCommits`. Returns an empty array once
  /// history runs out.
  func moreCommits(limit: Int) throws -> [Commit] {
    guard let walk else { return [] }
    var commits: [Commit] = []
    commits.reserveCapacity(limit)
    var oid = git_oid()

    while commits.count < limit {
      let code = git_revwalk_next(&oid, walk)
      if code == GIT_ITEROVER.rawValue { break }
      try GitError.check(code, "Couldn't read history.")

      var commit: OpaquePointer?
      try GitError.check(git_commit_lookup(&commit, handle, &oid), "Couldn't read a commit.")
      defer { git_commit_free(commit) }

      let author = git_commit_author(commit).pointee
      commits.append(
        Commit(
          id: Self.hex(oid),
          summary: git_commit_summary(commit).map { String(cString: $0) } ?? "",
          authorName: author.name.map { String(cString: $0) } ?? "",
          date: Date(timeIntervalSince1970: TimeInterval(author.when.time))))
    }
    return commits
  }

  // MARK: - Diff

  /// The diff of one commit against its first parent, or against an empty
  /// tree for a root commit.
  func diff(commitID: String) throws -> Diff {
    // A newer request usually supersedes this one while it waits its turn on
    // the actor. Skip the work rather than build a diff nobody will see.
    try Task.checkCancellation()

    var oid = git_oid()
    try GitError.check(git_oid_fromstr(&oid, commitID), "Bad commit id \(commitID).")

    var commit: OpaquePointer?
    try GitError.check(git_commit_lookup(&commit, handle, &oid), "Couldn't find \(commitID).")
    defer { git_commit_free(commit) }

    var tree: OpaquePointer?
    try GitError.check(git_commit_tree(&tree, commit), "Couldn't read the commit's files.")
    defer { git_tree_free(tree) }

    var parentTree: OpaquePointer?
    if git_commit_parentcount(commit) > 0 {
      var parent: OpaquePointer?
      try GitError.check(git_commit_parent(&parent, commit, 0), "Couldn't read the parent commit.")
      defer { git_commit_free(parent) }
      try GitError.check(git_commit_tree(&parentTree, parent), "Couldn't read the parent's files.")
    }
    defer { if let parentTree { git_tree_free(parentTree) } }

    var options = Self.diffOptions()
    var diff: OpaquePointer?
    try GitError.check(
      git_diff_tree_to_tree(&diff, handle, parentTree, tree, &options),
      "Couldn't diff \(commitID).")
    defer { git_diff_free(diff) }
    return try makeDiff(diff, source: .commit(commitID))
  }

  /// Uncommitted changes: staged (HEAD to index) or unstaged (index to working
  /// tree, untracked files included as all-new). `path` limits it to one file.
  func workingTreeDiff(staged: Bool, path: String?) throws -> Diff {
    try reloadIndex()
    var options = Self.diffOptions()
    if !staged {
      options.flags |=
        GIT_DIFF_INCLUDE_UNTRACKED.rawValue | GIT_DIFF_RECURSE_UNTRACKED_DIRS.rawValue
        | GIT_DIFF_SHOW_UNTRACKED_CONTENT.rawValue
    }
    if path != nil { options.flags |= GIT_DIFF_DISABLE_PATHSPEC_MATCH.rawValue }

    let diff = try withPathspec(path, &options) { options -> OpaquePointer? in
      var diff: OpaquePointer?
      if staged {
        var headTree: OpaquePointer?
        defer { if let headTree { git_tree_free(headTree) } }
        if git_repository_head_unborn(handle) != 1 {
          try GitError.check(git_revparse_single(&headTree, handle, "HEAD^{tree}"), "Couldn't read HEAD.")
        }
        try GitError.check(
          git_diff_tree_to_index(&diff, handle, headTree, nil, &options), "Couldn't diff staged changes.")
      } else {
        try GitError.check(
          git_diff_index_to_workdir(&diff, handle, nil, &options), "Couldn't diff changes.")
      }
      return diff
    }
    defer { git_diff_free(diff) }
    return try makeDiff(diff, source: .workingTree(staged: staged, path: path))
  }

  // MARK: - Branch diff

  /// The branch to compare against: the remote's default branch if it names
  /// one, else main or master, local or remote. Skips any that point at HEAD
  /// itself (on main, the local main is no comparison at all).
  func branchBase() -> (name: String, oid: git_oid)? {
    var head = git_oid()
    guard git_reference_name_to_id(&head, handle, "HEAD") == 0 else { return nil }
    var candidates: [String] = []
    var remoteHead: OpaquePointer?
    if git_reference_lookup(&remoteHead, handle, "refs/remotes/origin/HEAD") == 0, let remoteHead {
      if let target = git_reference_symbolic_target(remoteHead) {
        candidates.append(String(cString: target).replacingOccurrences(of: "refs/remotes/", with: ""))
      }
      git_reference_free(remoteHead)
    }
    candidates += ["main", "master", "origin/main", "origin/master"]
    for name in candidates {
      var oid = git_oid()
      let ref = name.hasPrefix("origin/") ? "refs/remotes/\(name)" : "refs/heads/\(name)"
      guard git_reference_name_to_id(&oid, handle, ref) == 0 else { continue }
      if git_oid_equal(&oid, &head) == 1 { continue }
      return (name, oid)
    }
    return nil
  }

  /// Everything the current branch changes since it split from its base:
  /// the merge base's tree against the working tree, so uncommitted work
  /// and untracked files are included, like reviewing a pull request before
  /// it's opened.
  func branchDiff() throws -> (Diff, BranchComparison) {
    guard let base = branchBase() else {
      throw GitError(code: -1, message: "There's no main or master branch to compare this branch with.")
    }
    try reloadIndex()
    var head = git_oid()
    try GitError.check(git_reference_name_to_id(&head, handle, "HEAD"), "Couldn't read HEAD.")
    var baseOID = base.oid
    var mergeBase = git_oid()
    try GitError.check(
      git_merge_base(&mergeBase, handle, &head, &baseOID), "This branch and \(base.name) share no history.")
    var ahead = 0
    var behind = 0
    git_graph_ahead_behind(&ahead, &behind, handle, &head, &mergeBase)

    var commit: OpaquePointer?
    try GitError.check(git_commit_lookup(&commit, handle, &mergeBase), "Couldn't read the merge base.")
    defer { git_commit_free(commit) }
    var tree: OpaquePointer?
    try GitError.check(git_commit_tree(&tree, commit), "Couldn't read the merge base's files.")
    defer { git_tree_free(tree) }

    var options = Self.diffOptions()
    options.flags |=
      GIT_DIFF_INCLUDE_UNTRACKED.rawValue | GIT_DIFF_RECURSE_UNTRACKED_DIRS.rawValue
      | GIT_DIFF_SHOW_UNTRACKED_CONTENT.rawValue
    var diff: OpaquePointer?
    try GitError.check(
      git_diff_tree_to_workdir_with_index(&diff, handle, tree, &options), "Couldn't diff this branch.")
    defer { git_diff_free(diff) }

    let comparison = BranchComparison(
      base: base.name, branch: info().branch, ahead: ahead, mergeBase: String(Self.hex(mergeBase).prefix(7)))
    return (try makeDiff(diff, source: .branch), comparison)
  }

  /// The size of what a commit would contain: the staged changes, or with
  /// `trackedOnly`, every change to tracked files (what Commit Tracked takes).
  /// Uses libgit2's diff stats, which skip building a patch per file.
  func commitSize(trackedOnly: Bool) throws -> ChangeSize {
    try reloadIndex()
    var options = Self.diffOptions()
    var diff: OpaquePointer?
    if trackedOnly {
      try GitError.check(git_diff_index_to_workdir(&diff, handle, nil, &options), "Couldn't measure changes.")
    } else {
      var headTree: OpaquePointer?
      defer { if let headTree { git_tree_free(headTree) } }
      if git_repository_head_unborn(handle) != 1 {
        try GitError.check(git_revparse_single(&headTree, handle, "HEAD^{tree}"), "Couldn't read HEAD.")
      }
      try GitError.check(
        git_diff_tree_to_index(&diff, handle, headTree, nil, &options), "Couldn't measure staged changes.")
    }
    defer { git_diff_free(diff) }
    var stats: OpaquePointer?
    try GitError.check(git_diff_get_stats(&stats, diff), "Couldn't measure changes.")
    defer { git_diff_stats_free(stats) }
    return ChangeSize(
      files: git_diff_stats_files_changed(stats), additions: git_diff_stats_insertions(stats),
      deletions: git_diff_stats_deletions(stats))
  }

  private static func diffOptions() -> git_diff_options {
    var options = git_diff_options()
    git_diff_options_init(&options, UInt32(GIT_DIFF_OPTIONS_VERSION))
    options.context_lines = 3
    // Histogram gave the better diff for 62.6% of changed code files, against
    // 16.9% for the default Myers (Nugroho et al., EMSE 2020). libgit2 needs a
    // local patch for it; see Packages/Clibgit2/VENDORED.md.
    options.flags |= GIT_DIFF_HISTOGRAM.rawValue
    // Rename and copy detection (git_diff_find_similar) is deliberately not
    // run: it is the expensive part of diffing. Renames show as delete + add.
    return options
  }

  /// Runs `body` with `options.pathspec` set to `path`, keeping the C string
  /// alive for the call.
  private func withPathspec<T>(
    _ path: String?, _ options: inout git_diff_options, _ body: (inout git_diff_options) throws -> T
  ) rethrows -> T {
    guard let path else { return try body(&options) }
    return try path.withCString { cPath in
      var strings: [UnsafeMutablePointer<CChar>?] = [UnsafeMutablePointer(mutating: cPath)]
      return try strings.withUnsafeMutableBufferPointer { buffer in
        options.pathspec = git_strarray(strings: buffer.baseAddress, count: 1)
        defer { options.pathspec = git_strarray() }
        return try body(&options)
      }
    }
  }

  private func makeDiff(_ diff: OpaquePointer?, source: DiffSource) throws -> Diff {
    let count = git_diff_num_deltas(diff)
    var files: [FileChange] = []
    files.reserveCapacity(count)
    for index in 0..<count {
      files.append(try fileChange(diff: diff, index: index))
    }
    // Most useful first (see FileOrder), renumbered so a file's id is still
    // its position: the diff view relies on that.
    let ordered = FileOrder.current.sorted(files, path: \.path).enumerated().map { $1.renumbered($0) }
    return Diff(source: source, files: ordered)
  }

  private func fileChange(diff: OpaquePointer?, index: Int) throws -> FileChange {
    var patch: OpaquePointer?
    try GitError.check(git_patch_from_diff(&patch, diff, index), "Couldn't build a file's diff.")
    defer { git_patch_free(patch) }

    // Read the delta from the patch, not the diff: binary detection happens
    // while the patch is generated and updates the delta's flags.
    let delta = (patch.map { git_patch_get_delta($0) } ?? git_diff_get_delta(diff, index)).pointee
    let status = Self.status(delta.status)
    let isBinary = delta.flags & GIT_DIFF_FLAG_BINARY.rawValue != 0
    let oldPath = status == .added ? nil : delta.old_file.path.map { String(cString: $0) }
    let newPath = status == .deleted ? nil : delta.new_file.path.map { String(cString: $0) }

    var hunks: [Hunk] = []
    var additions = 0
    var deletions = 0
    if let patch, !isBinary {
      var adds = 0
      var dels = 0
      git_patch_line_stats(nil, &adds, &dels, patch)
      additions = adds
      deletions = dels

      let hunkCount = git_patch_num_hunks(patch)
      hunks.reserveCapacity(hunkCount)
      for hunkIndex in 0..<hunkCount {
        hunks.append(try hunk(patch: patch, index: hunkIndex))
      }
    }

    return FileChange(
      id: index, status: status, oldPath: oldPath, newPath: newPath,
      isBinary: isBinary, hunks: hunks, additions: additions, deletions: deletions)
  }

  private func hunk(patch: OpaquePointer, index: Int) throws -> Hunk {
    var hunkPointer: UnsafePointer<git_diff_hunk>?
    var lineCount = 0
    try GitError.check(
      git_patch_get_hunk(&hunkPointer, &lineCount, patch, index), "Couldn't read a hunk.")
    let hunk = hunkPointer!.pointee

    var lines: [DiffLine] = []
    lines.reserveCapacity(lineCount)
    for lineIndex in 0..<lineCount {
      var linePointer: UnsafePointer<git_diff_line>?
      try GitError.check(
        git_patch_get_line_in_hunk(&linePointer, patch, index, lineIndex),
        "Couldn't read a line.")
      let line = linePointer!.pointee
      lines.append(Self.diffLine(line))
    }

    let header = withUnsafeBytes(of: hunk.header) { bytes in
      Self.text(bytes.baseAddress, count: min(Int(hunk.header_len), bytes.count))
    }
    return Hunk(
      id: index, header: header,
      oldStart: Int(hunk.old_start), oldCount: Int(hunk.old_lines),
      newStart: Int(hunk.new_start), newCount: Int(hunk.new_lines),
      lines: lines)
  }

  // MARK: - Conversion

  private static func diffLine(_ line: git_diff_line) -> DiffLine {
    let kind: DiffLine.Kind
    switch UInt8(bitPattern: line.origin) {
    case UInt8(ascii: "+"): kind = .addition
    case UInt8(ascii: "-"): kind = .deletion
    case UInt8(ascii: "="), UInt8(ascii: ">"), UInt8(ascii: "<"): kind = .noNewline
    default: kind = .context
    }
    if kind == .noNewline {
      return DiffLine(kind: kind, oldNumber: nil, newNumber: nil, text: "No newline at end of file")
    }
    return DiffLine(
      kind: kind,
      oldNumber: line.old_lineno > 0 ? Int(line.old_lineno) : nil,
      newNumber: line.new_lineno > 0 ? Int(line.new_lineno) : nil,
      text: text(line.content, count: line.content_len))
  }

  /// Decodes bytes as UTF-8 and drops the trailing line ending.
  private static func text(_ start: UnsafeRawPointer?, count: Int) -> String {
    guard let start, count > 0 else { return "" }
    var bytes = UnsafeRawBufferPointer(start: start, count: count)
    while let last = bytes.last, last == UInt8(ascii: "\n") || last == UInt8(ascii: "\r") {
      bytes = UnsafeRawBufferPointer(rebasing: bytes.dropLast())
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static func status(_ delta: git_delta_t) -> FileChange.Status {
    switch delta {
    case GIT_DELTA_ADDED, GIT_DELTA_UNTRACKED: .added
    case GIT_DELTA_DELETED: .deleted
    case GIT_DELTA_RENAMED: .renamed
    case GIT_DELTA_COPIED: .copied
    case GIT_DELTA_TYPECHANGE: .typeChanged
    default: .modified
    }
  }

  private static func hex(_ oid: git_oid) -> String {
    var oid = oid
    let size = Int(GIT_OID_SHA1_HEXSIZE)
    var buffer = [UInt8](repeating: 0, count: size)
    buffer.withUnsafeMutableBufferPointer { bytes in
      bytes.baseAddress!.withMemoryRebound(to: CChar.self, capacity: size) {
        _ = git_oid_fmt($0, &oid)
      }
    }
    return String(decoding: buffer, as: UTF8.self)
  }
}

/// A `git_strarray` that owns its C strings for as long as it lives.
private final class CStringArray {
  let array: git_strarray

  init(_ strings: [String]) {
    let buffer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(capacity: strings.count)
    for (index, string) in strings.enumerated() { buffer[index] = strdup(string) }
    array = git_strarray(strings: buffer, count: strings.count)
  }

  deinit {
    for index in 0..<array.count { free(array.strings[index]) }
    array.strings.deallocate()
  }
}
