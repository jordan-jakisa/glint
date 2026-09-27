import Foundation

/// Finds the repositories inside a folder that isn't one itself.
enum RepositoryDiscovery {
  /// Folders that hold dependencies or build output, never a project's own
  /// repositories, and can be huge. Hidden folders are skipped as well.
  static let skipped: Set<String> = [
    "node_modules", "bower_components", "vendor", "Pods", "Carthage", "DerivedData", "build",
    "dist", "target", "out", "venv", "env", "__pycache__", "site-packages",
  ]

  /// Repositories up to `maxDepth` folders down, sorted by path. A folder with
  /// a `.git` folder or file counts (linked worktrees and submodule-style
  /// checkouts use a file), and the search doesn't go inside a repository once
  /// it finds one.
  static func repositories(in root: URL, maxDepth: Int = 3) -> [WorkspaceRepository] {
    let fileManager = FileManager.default
    let root = root.standardizedFileURL
    var found: [WorkspaceRepository] = []
    var level = [root]

    for _ in 0..<maxDepth {
      var next: [URL] = []
      for folder in level {
        let children =
          (try? fileManager.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
        for child in children {
          let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
          guard values?.isDirectory == true, values?.isSymbolicLink != true,
            !skipped.contains(child.lastPathComponent)
          else { continue }
          if fileManager.fileExists(atPath: child.appendingPathComponent(".git").path) {
            found.append(WorkspaceRepository(url: child, relativePath: relativePath(of: child, in: root)))
          } else {
            next.append(child)
          }
        }
      }
      level = next
    }
    return found.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
  }

  private static func relativePath(of url: URL, in root: URL) -> String {
    let path = url.standardizedFileURL.path
    let base = root.path.hasSuffix("/") ? root.path : root.path + "/"
    return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
  }
}
