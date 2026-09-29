import SwiftUI

/// The Files tab: the project's files as a tree, like Zed's project panel.
/// Type to filter by path. Changed files take their status colour. Picking
/// one opens it in the editor on the right.
struct FilesView: View {
  @Bindable var session: RepositorySession
  @State private var query = ""
  @State private var expanded: Set<String> = []
  /// What's inside ignored folders you've opened, read from disk then.
  @State private var loadedFiles: Set<String> = []
  @State private var loadedFolders: Set<String> = []
  @AppStorage("filesShowIgnored") private var showsIgnored = true

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField("Filter files", text: $query)
          .textFieldStyle(.plain)
        Button {
          showsIgnored.toggle()
        } label: {
          Image(systemName: showsIgnored ? "eye" : "eye.slash").hitTarget()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel(showsIgnored ? "Hide ignored files" : "Show ignored files")
        .help(showsIgnored ? "Hide files .gitignore ignores, like .env" : "Show files .gitignore ignores, like .env")
      }
      .font(.app(.callout))
      .padding(.horizontal, 10)
      .frame(height: 28)
      Hairline()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(rows, id: \.id) { row in
              rowView(row).id(row.id)
            }
          }
          .padding(.vertical, 2)
        }
        .onChange(of: session.openedFilePath) { _, path in
          guard let path else { return }
          reveal(path)
          proxy.scrollTo("file:" + path)
        }
      }
    }
    .task(id: session.projectURL) { session.loadProjectFiles() }
    .onChange(of: session.repositorySummaries) { session.loadProjectFiles() }
    .onChange(of: session.status) { session.loadProjectFiles() }
    .onChange(of: showsIgnored) {
      loadedFiles = []
      loadedFolders = []
      session.loadProjectFiles()
    }
  }

  // MARK: Rows

  private struct Row {
    let id: String
    let path: String
    let name: String
    let depth: Int
    let isFolder: Bool
  }

  /// Folders first at each level, then files; only what's expanded. With a
  /// filter, the matching files, flat, by path.
  private var rows: [Row] {
    let trimmed = query.trimmingCharacters(in: .whitespaces)
    if !trimmed.isEmpty {
      return session.projectFiles.lazy
        .filter { $0.localizedCaseInsensitiveContains(trimmed) }
        .prefix(500)
        .map { Row(id: "file:" + $0, path: $0, name: $0, depth: 0, isFolder: false) }
    }
    var tree = Node()
    for path in session.projectFiles { tree.insert(path.split(separator: "/").map(String.init)) }
    for path in loadedFiles { tree.insert(path.split(separator: "/").map(String.init)) }
    for folder in session.ignoredFolders.union(loadedFolders) {
      tree.insertFolder(folder.split(separator: "/").map(String.init))
    }
    var rows: [Row] = []
    func walk(_ node: Node, prefix: String, depth: Int) {
      for name in node.folders.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
        let path = prefix.isEmpty ? name : prefix + "/" + name
        rows.append(Row(id: "folder:" + path, path: path, name: name, depth: depth, isFolder: true))
        if expanded.contains(path) { walk(node.folders[name]!, prefix: path, depth: depth + 1) }
      }
      for name in node.files.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
        let path = prefix.isEmpty ? name : prefix + "/" + name
        rows.append(Row(id: "file:" + path, path: path, name: name, depth: depth, isFolder: false))
      }
    }
    walk(tree, prefix: "", depth: 0)
    return rows
  }

  private struct Node {
    var folders: [String: Node] = [:]
    var files: [String] = []

    mutating func insertFolder(_ parts: [String]) {
      guard let first = parts.first else { return }
      folders[first, default: Node()].insertFolder(Array(parts.dropFirst()))
    }

    mutating func insert(_ parts: [String]) {
      guard let first = parts.first else { return }
      if parts.count == 1 {
        files.append(first)
      } else {
        folders[first, default: Node()].insert(Array(parts.dropFirst()))
      }
    }
  }

  private func rowView(_ row: Row) -> some View {
    let isOpen = !row.isFolder && row.path == session.openedFilePath
    let kind = row.isFolder ? nil : changes[row.path]
    let ignored = isIgnored(row.path)
    return HStack(spacing: 6) {
      if row.isFolder {
        Image(systemName: expanded.contains(row.path) ? "chevron.down" : "chevron.right")
          .font(.app(.caption2))
          .foregroundStyle(.secondary)
          .frame(width: 12)
        Image(systemName: "folder")
          .foregroundStyle(.secondary)
      } else {
        Color.clear.frame(width: 12)
        Image(systemName: "doc.text")
          .foregroundStyle(.secondary)
      }
      Text(row.name)
        .foregroundStyle(kind.map { Color(nsColor: Self.color($0)) } ?? (ignored ? .secondary : .primary))
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 0)
      if isOpen, session.openedFile?.hasUnsavedChanges == true {
        Circle().fill(.secondary).frame(width: 6, height: 6)
          .help("Not saved yet: \u{2318}S saves")
      }
    }
    .font(.app(.body))
    .padding(.leading, 10 + CGFloat(row.depth) * 16)
    .padding(.trailing, 10)
    .frame(height: 26)
    .background(isOpen ? Color.themeAccent.opacity(0.12) : .clear)
    .contentShape(Rectangle())
    .onTapGesture {
      if row.isFolder {
        if expanded.contains(row.path) {
          expanded.remove(row.path)
        } else {
          expanded.insert(row.path)
          loadIgnoredFolder(row.path)
        }
      } else {
        session.showFile(row.path)
      }
    }
    .help(row.path)
    .contextMenu {
      let url = session.filesRoot?.appendingPathComponent(row.path)
      if !row.isFolder {
        Button("Open in Default App") { url.map { NSWorkspace.shared.open($0) } }
        Divider()
      }
      Button("Copy Path") { url.map { session.copyPath($0.path) } }
      Button("Copy Relative Path") { session.copyPath(row.path) }
      Button("Reveal in Finder") { url.map { NSWorkspace.shared.activateFileViewerSelecting([$0]) } }
    }
  }

  /// Whether `.gitignore` hides this path, or a folder above it.
  private func isIgnored(_ path: String) -> Bool {
    if session.ignoredFiles.contains(path) { return true }
    let folders = session.ignoredFolders
    guard !folders.isEmpty else { return false }
    var folder = path
    while !folder.isEmpty {
      if folders.contains(folder) { return true }
      folder = (folder as NSString).deletingLastPathComponent
    }
    return false
  }

  /// An ignored folder's contents, one level, read when you open it: git
  /// doesn't list inside them, and `node_modules` could be huge.
  private func loadIgnoredFolder(_ path: String) {
    guard isIgnored(path), let root = session.filesRoot else { return }
    let url = root.appendingPathComponent(path)
    guard
      let children = try? FileManager.default.contentsOfDirectory(
        at: url, includingPropertiesForKeys: [.isDirectoryKey])
    else { return }
    for child in children where child.lastPathComponent != ".DS_Store" {
      let childPath = path + "/" + child.lastPathComponent
      if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        loadedFolders.insert(childPath)
      } else {
        loadedFiles.insert(childPath)
      }
    }
  }

  /// Opens every folder above `path`, so the open file shows in the tree.
  private func reveal(_ path: String) {
    let parts = path.split(separator: "/").dropLast()
    for depth in parts.indices {
      expanded.insert(parts[...depth].joined(separator: "/"))
    }
  }

  private var changes: [String: ChangedFile.Kind] {
    let prefix = session.activeFilesPrefix
    return Dictionary(session.status.entries.map { (prefix + $0.path, $0.kind) }, uniquingKeysWith: { a, _ in a })
  }

  private static func color(_ kind: ChangedFile.Kind) -> NSColor {
    let theme = Theme.shared
    return switch kind {
    case .added, .untracked: theme.createdLabel
    case .deleted: theme.deletedLabel
    case .modified, .typeChanged: theme.modified
    case .renamed: theme.renamed
    case .conflicted: theme.conflicted
    }
  }
}

/// The Files tab's right side: the open file in the editor, saved with ⌘S
/// and kept in step with the file on disk.
struct FileEditorPane: View {
  @Bindable var session: RepositorySession

  var body: some View {
    if let edit = session.openedFile, let path = session.openedFilePath {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          Text(edit.fileName).font(.code(.body)).fontWeight(.semibold)
          Text((path as NSString).deletingLastPathComponent)
            .font(.code(.body))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
          if edit.hasUnsavedChanges {
            Circle().fill(.secondary).frame(width: 6, height: 6)
          }
          Spacer()
          if let note = edit.note {
            Text(note).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
          }
          if let language = edit.language {
            Text(language.name).font(.app(.caption)).foregroundStyle(.secondary)
          }
          Button("Save", action: session.saveOpenedFile)
            .keyboardShortcut("s")
            .disabled(!edit.hasUnsavedChanges)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        Hairline()
        CodeEditor(text: Bindable(edit).text, language: edit.language, firstLine: 1)
          .id(edit.id)
      }
    } else {
      EmptyState(
        "Pick a file", systemImage: "doc.text",
        description: Text("Open any file in the project from the list. It saves as you type."))
    }
  }
}
