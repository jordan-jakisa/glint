import Foundation

/// The Files tab's rows: the project as a tree, folders first at each level,
/// only what's expanded. With a filter, the matching files, flat, by path.
enum FileTree {
  struct Row: Equatable, Sendable {
    let id: String
    let path: String
    let name: String
    let depth: Int
    let isFolder: Bool
  }

  /// `files` are paths from the root; `folders` are folders to show even
  /// with nothing known inside (ignored ones, read when opened).
  static func rows(files: [String], folders: Set<String>, expanded: Set<String>, query: String) -> [Row] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty {
      return files.lazy
        .filter { $0.localizedCaseInsensitiveContains(trimmed) }
        .prefix(500)
        .map { Row(id: "file:" + $0, path: $0, name: $0, depth: 0, isFolder: false) }
    }
    var tree = Node()
    for path in files { tree.insert(path.split(separator: "/").map(String.init)) }
    for folder in folders { tree.insertFolder(folder.split(separator: "/").map(String.init)) }
    var rows: [Row] = []
    func walk(_ node: Node, prefix: String, depth: Int) {
      for name in node.folders.keys.sorted(by: order) {
        let path = prefix.isEmpty ? name : prefix + "/" + name
        rows.append(Row(id: "folder:" + path, path: path, name: name, depth: depth, isFolder: true))
        if expanded.contains(path) { walk(node.folders[name]!, prefix: path, depth: depth + 1) }
      }
      for name in node.files.sorted(by: order) {
        let path = prefix.isEmpty ? name : prefix + "/" + name
        rows.append(Row(id: "file:" + path, path: path, name: name, depth: depth, isFolder: false))
      }
    }
    walk(tree, prefix: "", depth: 0)
    return rows
  }

  private static func order(_ a: String, _ b: String) -> Bool {
    a.localizedStandardCompare(b) == .orderedAscending
  }

  private struct Node {
    var folders: [String: Node] = [:]
    var files: Set<String> = []

    mutating func insertFolder(_ parts: [String]) {
      guard let first = parts.first else { return }
      folders[first, default: Node()].insertFolder(Array(parts.dropFirst()))
    }

    mutating func insert(_ parts: [String]) {
      guard let first = parts.first else { return }
      if parts.count == 1 {
        files.insert(first)
      } else {
        folders[first, default: Node()].insert(Array(parts.dropFirst()))
      }
    }
  }
}
