import Foundation

/// Merge conflicts: a conflicted file shows its conflicts in place of the
/// diff, and each one resolves to your side, theirs, or both, straight in the
/// file on disk. Staging the file then marks it resolved.
extension RepositorySession {
  /// The conflicted file selected in Changes, if that's what's selected.
  var selectedConflictPath: String? {
    guard tab == .changes, let selection = selectedChange, !selection.staged, let path = selection.path,
      status.unstaged.contains(where: { $0.path == path && $0.kind == .conflicted })
    else { return nil }
    return path
  }

  /// Reads the selected conflicted file from disk. Called when it's selected
  /// and whenever the watcher reloads it.
  func loadConflict(_ path: String) async {
    guard let repository else { return }
    let url = repository.url.appendingPathComponent(path)
    let document = await Task.detached(priority: .userInitiated) {
      ConflictDocument(path: path, content: try? String(contentsOf: url, encoding: .utf8))
    }.value
    guard selectedConflictPath == path, document != conflictDocument else { return }
    conflictDocument = document
  }

  /// Rewrites one conflict in the file as `choice`. Refuses if the file
  /// changed since it was shown, rather than overwrite work it hasn't seen.
  func resolveConflict(_ region: ConflictRegion, as choice: ConflictChoice) {
    guard let repository, let document = conflictDocument, let loaded = document.content else { return }
    let fileName = (document.path as NSString).lastPathComponent
    let url = repository.url.appendingPathComponent(document.path)
    do {
      let current = try String(contentsOf: url, encoding: .utf8)
      guard let output = Self.resolving(region, as: choice, loaded: loaded, current: current) else {
        alert = UserAlert(
          "Couldn't resolve this conflict",
          message: "\(fileName) changed since it was shown. Look at it again, then pick a side.")
        Task { await loadConflict(document.path) }
        return
      }
      try output.write(to: url, atomically: true, encoding: .utf8)
      Timing.writes.notice("resolve conflict")
      conflictDocument = ConflictDocument(path: document.path, content: output)
    } catch {
      alert = UserAlert("Couldn't resolve this conflict", error: error)
    }
  }

  /// The file with `region` resolved, or nil if what's on disk isn't what
  /// was shown.
  nonisolated static func resolving(
    _ region: ConflictRegion, as choice: ConflictChoice, loaded: String, current: String
  ) -> String? {
    guard current == loaded else { return nil }
    return Conflict.resolving(region: region, choice: choice, in: current)
  }
}
