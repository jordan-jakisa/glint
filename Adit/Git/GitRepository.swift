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

  /// Opens the repository at exactly `url`, without searching parent folders.
  /// The sandbox only grants access to the folder the user picked, so a
  /// repository found by walking upward could not be read anyway.
  @concurrent
  static func open(at url: URL) async throws -> GitRepository {
    _ = LibGit2.initialized
    var repo: OpaquePointer?
    let code = url.withUnsafeFileSystemRepresentation { path in
      git_repository_open_ext(
        &repo, path, GIT_REPOSITORY_OPEN_NO_SEARCH.rawValue, nil)
    }
    if code == GIT_ENOTFOUND.rawValue {
      throw GitError(
        code: code,
        message: "\(url.lastPathComponent) isn't a git repository. Pick the folder that contains .git.")
    }
    try GitError.check(code, "Couldn't open \(url.path).")
    return GitRepository(url: url, handle: repo!)
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
  func diff(commitID: String) throws -> CommitDiff {
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

    var options = git_diff_options()
    git_diff_options_init(&options, UInt32(GIT_DIFF_OPTIONS_VERSION))
    options.context_lines = 3
    // Rename and copy detection (git_diff_find_similar) is deliberately not
    // run: it is the expensive part of diffing. Renames show as delete + add.

    var diff: OpaquePointer?
    try GitError.check(
      git_diff_tree_to_tree(&diff, handle, parentTree, tree, &options),
      "Couldn't diff \(commitID).")
    defer { git_diff_free(diff) }

    let count = git_diff_num_deltas(diff)
    var files: [FileChange] = []
    files.reserveCapacity(count)
    for index in 0..<count {
      files.append(try fileChange(diff: diff, index: index))
    }
    return CommitDiff(commitID: commitID, files: files)
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
