import Clibgit2
import Foundation

/// Builds throwaway repositories on disk with libgit2, so tests exercise real
/// git data without shelling out to `git` (which the sandboxed test host can't
/// run).
final class FixtureRepository {
  let url: URL
  private let repo: OpaquePointer
  private var time: Int64 = 1_700_000_000

  init() throws {
    git_libgit2_init()
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("adit-fixture-\(UUID().uuidString)", isDirectory: true)
    var repo: OpaquePointer?
    try Self.check(git_repository_init(&repo, url.path, 0))
    self.repo = repo!
  }

  deinit {
    git_repository_free(repo)
    try? FileManager.default.removeItem(at: url)
  }

  /// Writes `files` (nil deletes), stages everything, and commits. Returns the
  /// new commit's hex id.
  @discardableResult
  func commit(_ message: String, files: [String: String?]) throws -> String {
    try commit(message, data: files.mapValues { $0.map { Data($0.utf8) } })
  }

  @discardableResult
  func commit(_ message: String, data files: [String: Data?]) throws -> String {
    var index: OpaquePointer?
    try Self.check(git_repository_index(&index, repo))
    defer { git_index_free(index) }

    for (path, contents) in files {
      let fileURL = url.appendingPathComponent(path)
      if let contents {
        try FileManager.default.createDirectory(
          at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: fileURL)
        try Self.check(git_index_add_bypath(index, path))
      } else {
        try FileManager.default.removeItem(at: fileURL)
        try Self.check(git_index_remove_bypath(index, path))
      }
    }
    try Self.check(git_index_write(index))

    var treeID = git_oid()
    try Self.check(git_index_write_tree(&treeID, index))
    var tree: OpaquePointer?
    try Self.check(git_tree_lookup(&tree, repo, &treeID))
    defer { git_tree_free(tree) }

    time += 60
    var signature: UnsafeMutablePointer<git_signature>?
    try Self.check(git_signature_new(&signature, "Test Author", "test@example.com", time, 0))
    defer { git_signature_free(signature) }

    var parentID = git_oid()
    var parent: OpaquePointer?
    if git_reference_name_to_id(&parentID, repo, "HEAD") == 0 {
      try Self.check(git_commit_lookup(&parent, repo, &parentID))
    }
    defer { if let parent { git_commit_free(parent) } }

    var commitID = git_oid()
    var parents: [OpaquePointer?] = parent.map { [$0] } ?? []
    try Self.check(
      git_commit_create(
        &commitID, repo, "HEAD", signature, signature, nil, message, tree,
        parents.count, &parents))

    var buffer = [CChar](repeating: 0, count: 41)
    git_oid_tostr(&buffer, buffer.count, &commitID)
    return String(decoding: buffer.prefix(40).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  /// Writes a file in the working tree without staging it.
  func write(_ path: String, _ contents: String) throws {
    let fileURL = url.appendingPathComponent(path)
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(contents.utf8).write(to: fileURL)
  }

  func delete(_ path: String) throws {
    try FileManager.default.removeItem(at: url.appendingPathComponent(path))
  }

  /// Stages one path the way `git add` would, through a separate index handle,
  /// like another tool would.
  func stage(_ path: String) throws {
    var index: OpaquePointer?
    try Self.check(git_repository_index(&index, repo))
    defer { git_index_free(index) }
    try Self.check(git_index_read(index, 1))
    try Self.check(git_index_add_bypath(index, path))
    try Self.check(git_index_write(index))
  }

  /// The staged contents of `path`, or nil if it isn't in the index.
  func indexContents(_ path: String) throws -> String? {
    var index: OpaquePointer?
    try Self.check(git_repository_index(&index, repo))
    defer { git_index_free(index) }
    try Self.check(git_index_read(index, 1))
    guard let entry = git_index_get_bypath(index, path, 0) else { return nil }
    var oid = entry.pointee.id
    var blob: OpaquePointer?
    try Self.check(git_blob_lookup(&blob, repo, &oid))
    defer { git_blob_free(blob) }
    let size = Int(git_blob_rawsize(blob))
    let bytes = UnsafeRawBufferPointer(start: git_blob_rawcontent(blob), count: size)
    return String(decoding: bytes, as: UTF8.self)
  }

  /// Current HEAD commit message summary, or nil for an empty repository.
  func headSummary() throws -> String? {
    var oid = git_oid()
    guard git_reference_name_to_id(&oid, repo, "HEAD") == 0 else { return nil }
    var commit: OpaquePointer?
    try Self.check(git_commit_lookup(&commit, repo, &oid))
    defer { git_commit_free(commit) }
    return git_commit_summary(commit).map { String(cString: $0) }
  }

  private static func check(_ code: Int32) throws {
    guard code < 0 else { return }
    let message = git_error_last().flatMap { $0.pointee.message.map { String(cString: $0) } }
    throw FixtureError(message: message ?? "libgit2 error \(code)")
  }
}

struct FixtureError: Error {
  let message: String
}
