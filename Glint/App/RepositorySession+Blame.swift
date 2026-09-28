import AppKit

/// Which version of a file a blame describes.
enum BlameRevision: Hashable, Sendable {
  /// The file on disk, as `git blame -- <path>` sees it.
  case workingTree
  /// The staged file, blamed with `--contents` from the index.
  case index
  case commit(String)
}

struct BlameKey: Hashable, Sendable {
  let repository: URL
  let path: String
  let revision: BlameRevision
  /// HEAD when the blame was asked for. Uncommitted blames go stale when you
  /// commit, so a new HEAD means a new key. Nil for commits, which never
  /// change.
  let head: String?
}

/// Blames by file and revision. Small and bounded: only files you've looked
/// at with blame on, or selected a line in.
struct BlameStore {
  private(set) var entries: [BlameKey: Blame] = [:]
  private var order: [BlameKey] = []
  var loading: Set<BlameKey> = []
  /// Keys git couldn't blame (a new file, a binary), so they aren't retried
  /// on every redraw.
  var failed: Set<BlameKey> = []
  /// The rows version a stale blame was last reloaded for, so a file that
  /// keeps disagreeing with its diff reloads once per diff, not per redraw.
  var reloadedFor: [BlameKey: Int] = [:]

  static let capacity = 48

  subscript(key: BlameKey) -> Blame? { entries[key] }

  mutating func store(_ blame: Blame, for key: BlameKey) {
    if entries.updateValue(blame, forKey: key) == nil { order.append(key) }
    if order.count > Self.capacity {
      let evicted = order.removeFirst()
      entries[evicted] = nil
      reloadedFor[evicted] = nil
    }
  }
}

/// Blame, like Zed's: a gutter column with who last changed each line and
/// when, and the selected line's author and summary after its text. Loaded
/// with system git, off the main thread, only for files the diff draws.
extension RepositorySession {
  /// Zed's `git: blame`. Shows or hides the blame column.
  func toggleBlame() {
    isBlameShown.toggle()
  }

  /// Who last changed `line` of the diff's file at `fileIndex`, for the new
  /// side (context and added lines). Nil until that file's blame is loaded;
  /// asking starts the load, and `blameVersion` changes when it lands.
  func blame(file fileIndex: Int, line: DiffLine) -> BlameCommit? {
    guard line.kind == .context || line.kind == .addition, let number = line.newNumber,
      let diff, diff.files.indices.contains(fileIndex)
    else { return nil }
    let file = diff.files[fileIndex]
    guard let path = file.newPath, !file.isBinary, let key = blameKey(path: path, source: diff.source) else {
      return nil
    }
    // A new file in your working copy has no history to ask git about.
    if file.status == .added, case .workingTree = diff.source { return .uncommitted }
    guard let blame = blames[key] else {
      if !blames.failed.contains(key) { loadBlame(key) }
      return nil
    }
    if let entry = blame.line(number), entry.matches(line.text) { return entry.commit }
    // The file moved on since this blame was loaded. Reload it, once for
    // this diff, and show nothing for the lines that don't match meanwhile.
    if blames.reloadedFor[key] != rowsVersion {
      blames.reloadedFor[key] = rowsVersion
      loadBlame(key)
    }
    return nil
  }

  private func blameKey(path: String, source: DiffSource) -> BlameKey? {
    guard let repository else { return nil }
    let head = commits.first?.id ?? ""
    switch source {
    case .commit(let id):
      return BlameKey(repository: repository.url, path: path, revision: .commit(id), head: nil)
    case .workingTree(true, _):
      return BlameKey(repository: repository.url, path: path, revision: .index, head: head)
    case .workingTree(false, _), .branch:
      return BlameKey(repository: repository.url, path: path, revision: .workingTree, head: head)
    }
  }

  private func loadBlame(_ key: BlameKey) {
    guard !blames.loading.contains(key) else { return }
    blames.loading.insert(key)
    let git = SystemGit(directory: key.repository)
    Task {
      let start = ContinuousClock.now
      let loaded = try? await Self.blame(of: key.path, at: key.revision, git: git)
      blames.loading.remove(key)
      if let loaded {
        Timing.report("blame", since: start, budget: 200)
        blames.store(loaded, for: key)
        blameVersion += 1
      } else {
        blames.failed.insert(key)
      }
    }
  }

  /// Runs `git blame --porcelain` for one file and parses it, all off the
  /// main thread.
  @concurrent
  nonisolated static func blame(of path: String, at revision: BlameRevision, git: SystemGit) async throws -> Blame {
    let output: String
    switch revision {
    case .workingTree:
      output = try await git.run(["blame", "--porcelain", "--", path])
    case .index:
      let staged = try await git.run(["show", ":\(path)"])
      output = try await git.run(["blame", "--porcelain", "--contents", "-", "--", path], input: staged)
    case .commit(let id):
      output = try await git.run(["blame", "--porcelain", id, "--", path])
    }
    return Blame.parse(porcelain: output)
  }
}

// MARK: - Permalinks

/// Links to a line or file on GitHub, GitLab, Bitbucket, Codeberg or Gitea,
/// and SourceHut, like Zed's "Copy Permalink to Line". Working-copy links
/// point at HEAD, the last commit; commit diffs link to that commit.
extension RepositorySession {
  func copyPermalink(to row: DiffRowID) {
    guard let target = permalinkTarget(for: row) else { return }
    makePermalink(target) { Self.copy($0) }
  }

  func openPermalink(to row: DiffRowID) {
    guard let target = permalinkTarget(for: row) else { return }
    makePermalink(target) { NSWorkspace.shared.open($0) }
  }

  /// Whether a diff row can be linked to: any line with a number.
  func canLinkToLine(_ row: DiffRowID) -> Bool { permalinkTarget(for: row) != nil }

  /// A caveat for the menu item's tooltip, when the link won't show exactly
  /// what you see.
  func permalinkNote(for row: DiffRowID) -> String? {
    guard let target = permalinkTarget(for: row), target.isUncommitted else { return nil }
    return "This line isn't committed yet, so the link points at your last commit."
  }

  /// The file's page, from the Changes list. Points at your last commit.
  func copyFilePermalink(_ path: String) {
    makePermalink(PermalinkTarget(path: path, line: nil, revision: .head, isUncommitted: false)) { Self.copy($0) }
  }

  func openFilePermalink(_ path: String) {
    makePermalink(PermalinkTarget(path: path, line: nil, revision: .head, isUncommitted: false)) {
      NSWorkspace.shared.open($0)
    }
  }

  struct PermalinkTarget {
    enum Revision {
      case head
      case commit(String)
      /// The commit's first parent, for a line the commit removed.
      case parent(String)
    }

    let path: String
    let line: Int?
    let revision: Revision
    let isUncommitted: Bool
  }

  /// The file and line a diff row shows: the new side where there is one,
  /// the old side for a removed line.
  private func permalinkTarget(for row: DiffRowID) -> PermalinkTarget? {
    guard let diff, diff.files.indices.contains(row.file), row.hunk >= 0, row.line >= 0 else { return nil }
    let file = diff.files[row.file]
    guard file.hunks.indices.contains(row.hunk) else { return nil }
    let hunk = file.hunks[row.hunk]
    let line: DiffLine?
    switch layout {
    case .unified:
      line = hunk.lines.indices.contains(row.line) ? hunk.lines[row.line] : nil
    case .split:
      let pair = hunk.splitRows.indices.contains(row.line) ? hunk.splitRows[row.line] : nil
      line = pair.flatMap { $0.right?.kind == .noNewline ? $0.left : ($0.right ?? $0.left) }
    }
    guard let line else { return nil }
    let isOld = line.kind == .deletion
    guard let number = isOld ? line.oldNumber : line.newNumber,
      let path = isOld ? file.oldPath : file.newPath
    else { return nil }
    switch diff.source {
    case .commit(let id):
      return PermalinkTarget(path: path, line: number, revision: isOld ? .parent(id) : .commit(id), isUncommitted: false)
    case .workingTree, .branch:
      let committed = isOld || (blame(file: row.file, line: line)?.isCommitted ?? (line.kind == .context))
      return PermalinkTarget(path: path, line: number, revision: .head, isUncommitted: !committed)
    }
  }

  /// Works out the remote and commit, then hands the link to `use`, or says
  /// plainly why there isn't one.
  private func makePermalink(_ target: PermalinkTarget, _ use: @escaping @MainActor (URL) -> Void) {
    guard let repository else { return }
    let git = SystemGit(directory: repository.url)
    let branch = info?.branch
    Task {
      let fallback = await repository.defaultRemote()
      guard let remote = await Self.remoteURL(git: git, branch: branch, fallback: fallback) else {
        alert = UserAlert(
          "No remote to link to",
          message: "This repository doesn't have a remote yet, so there's no page to link to. Add one with git remote add origin <url> in the terminal (\(AppCommand.showTerminal.keys)).")
        return
      }
      guard let site = Permalink.repository(fromRemote: remote) else {
        alert = UserAlert(
          "Can't link to this remote",
          message: "Links work for GitHub, GitLab, Bitbucket, Codeberg, Gitea and SourceHut. Your remote is \(remote), which isn't one of them.")
        return
      }
      guard let sha = await Self.resolve(target.revision, git: git) else {
        alert = UserAlert(
          "Nothing to link to yet",
          message: "Links point at a commit, and this branch doesn't have one yet. Commit first, then try again.")
        return
      }
      guard let url = Permalink.url(for: site, sha: sha, path: target.path, line: target.line) else { return }
      use(url)
    }
  }

  /// The branch's upstream remote, else `fallback` (origin, or the only
  /// one), as its URL.
  @concurrent
  nonisolated private static func remoteURL(git: SystemGit, branch: String?, fallback: String?) async -> String? {
    var name: String?
    if let branch {
      name = try? await git.run(["config", "--get", "branch.\(branch).remote"])
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    // "." means the upstream is a local branch, which has no web page.
    if name == nil || name == "" || name == "." { name = fallback }
    guard let name else { return nil }
    let url = try? await git.run(["remote", "get-url", name]).trimmingCharacters(in: .whitespacesAndNewlines)
    return url?.isEmpty == false ? url : nil
  }

  @concurrent
  nonisolated private static func resolve(_ revision: PermalinkTarget.Revision, git: SystemGit) async -> String? {
    let spec: String
    switch revision {
    case .head: spec = "HEAD"
    case .commit(let id): return id
    case .parent(let id): spec = "\(id)^"
    }
    let sha = try? await git.run(["rev-parse", "--verify", "--quiet", spec]).trimmingCharacters(in: .whitespacesAndNewlines)
    if sha?.isEmpty == false { return sha }
    // A root commit has no parent; its own page is the closest there is.
    if case .parent(let id) = revision { return id }
    return nil
  }

  private static func copy(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.absoluteString, forType: .string)
  }
}
