import SwiftUI

/// The Changes list as Zed's git panel draws it: one row per file with a
/// checkbox for its staged state (checked, partly, or not), the name in its
/// status colour and the folder dimmed, grouped into Conflicts, Tracked and
/// Untracked, flat or as a tree. Used in Style Zed.
struct ZedChangesList: View {
  @Bindable var session: RepositorySession
  @AppStorage("gitPanelTree") private var isTree = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Hairline()
      ScrollViewReader { proxy in
        List(selection: $session.selectedChange) {
          section("Conflicts", entries.filter { $0.kind == .conflicted })
          section("Tracked", entries.filter { $0.kind != .conflicted && $0.kind != .untracked })
          section("Untracked", entries.filter { $0.kind == .untracked })
        }
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 22)
        .onChange(of: session.selectedChange) { _, selection in
          if let selection, selection.path != nil { proxy.scrollTo(selection) }
        }
      }
    }
  }

  // MARK: Header

  /// Zed's panel header: how many changes, flat or tree, and Stage All.
  private var header: some View {
    HStack(spacing: 8) {
      Text(entries.count == 1 ? "1 change" : "\(entries.count) changes")
        .foregroundStyle(.secondary)
      Spacer()
      Button {
        isTree.toggle()
      } label: {
        Image(systemName: isTree ? "list.bullet.indent" : "list.bullet").hitTarget()
      }
      .buttonStyle(.borderless)
      .accessibilityLabel(isTree ? "Show as a list" : "Show as a tree")
      .help(isTree ? "Show as a list" : "Show as a tree")
      Button(allStaged ? "Unstage All" : "Stage All") {
        allStaged ? session.unstageAll() : session.stageAll()
      }
      .buttonStyle(.borderless)
      .help(allStaged ? AppCommand.unstageAll.hint("Unstage every file") : AppCommand.stageAll.hint("Stage every file"))
    }
    .font(.app(.callout))
    .padding(.horizontal, 10)
    .frame(height: 30)
  }

  // MARK: Sections and rows

  @ViewBuilder private func section(_ title: String, _ items: [Entry]) -> some View {
    if !items.isEmpty {
      Section {
        ForEach(rows(for: items)) { row in
          switch row {
          case .folder(let path, let depth):
            FolderRow(name: (path as NSString).lastPathComponent, depth: depth)
          case .file(let entry, let depth):
            fileRow(entry, depth: depth)
          }
        }
      } header: {
        HStack(spacing: 6) {
          StageBox(state: Self.state(of: items)) { stage(items, Self.state(of: items) != .all) }
          Text(title)
          Text("\(items.count)").foregroundStyle(.tertiary)
          Spacer()
        }
        .font(.app(.caption))
      }
    }
  }

  private func fileRow(_ entry: Entry, depth: Int) -> some View {
    HStack(spacing: 6) {
      StageBox(state: entry.state) { session.setStaged(entry.path, entry.state != .all) }
      Text(entry.fileName)
        .foregroundStyle(Color(nsColor: Self.labelColor(entry.kind)))
        .strikethrough(entry.kind == .deleted)
        .lineLimit(1)
      if !isTree {
        Text(entry.directory)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.head)
      }
      Spacer(minLength: 0)
    }
    .font(.app(.body))
    .padding(.leading, CGFloat(depth) * 12)
    .tag(entry.selection)
    .help(entry.path)
    .contextMenu { menu(for: entry) }
  }

  @ViewBuilder private func menu(for entry: Entry) -> some View {
    Button("Open File") { session.openFile(entry.path) }
    Button("Open Diff") { session.selectedChange = entry.selection }
    Button("View File History") { session.showHistory(for: entry.path) }
    Divider()
    Button(entry.state == .all ? "Unstage" : "Stage") { session.setStaged(entry.path, entry.state != .all) }
    if entry.kind == .untracked {
      Button("Trash Untracked File\u{2026}") { session.requestDiscard([entry.path]) }
    } else if entry.kind != .conflicted, entry.hasUnstaged {
      Button("Restore File\u{2026}") { session.requestDiscard([entry.path]) }
    }
    if entry.kind != .added, entry.kind != .untracked {
      Divider()
      Button("Copy File Permalink") { session.copyFilePermalink(entry.path) }
      Button("Open File Permalink") { session.openFilePermalink(entry.path) }
    }
    Divider()
    Button("Reveal in Finder") { session.revealInFinder(entry.path) }
    Button("Copy Path") { session.copyPath(entry.path) }
  }

  private func stage(_ items: [Entry], _ staged: Bool) {
    for item in items where (item.state == .all) != staged { session.setStaged(item.path, staged) }
  }

  // MARK: Model

  enum StageState { case none, partial, all }

  struct Entry: Identifiable, Hashable {
    let path: String
    let kind: ChangedFile.Kind
    let state: StageState
    let hasUnstaged: Bool
    var id: String { path }
    var fileName: String { (path as NSString).lastPathComponent }
    var directory: String { (path as NSString).deletingLastPathComponent }
    /// The diff to show: what's still unstaged if anything is, else what's
    /// staged.
    var selection: ChangeSelection { ChangeSelection(staged: !hasUnstaged, path: path) }
  }

  enum Row: Identifiable {
    case folder(String, depth: Int)
    case file(Entry, depth: Int)
    var id: String {
      switch self {
      case .folder(let path, _): "folder:" + path
      case .file(let entry, _): "file:" + entry.path
      }
    }
  }

  /// Each path once, staged and unstaged together, sorted by path.
  private var entries: [Entry] {
    let staged = Dictionary(session.status.staged.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    let unstaged = Dictionary(session.status.unstaged.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
    return Set(staged.keys).union(unstaged.keys).sorted().map { path in
      let kind = unstaged[path]?.kind ?? staged[path]!.kind
      let state: StageState =
        unstaged[path] == nil ? .all : (staged[path] == nil ? .none : .partial)
      return Entry(path: path, kind: kind, state: state, hasUnstaged: unstaged[path] != nil)
    }
  }

  private var allStaged: Bool { !entries.isEmpty && entries.allSatisfy { $0.state == .all } }

  /// Flat: the files. Tree: each folder once, before its files, indented.
  private func rows(for items: [Entry]) -> [Row] {
    guard isTree else { return items.map { .file($0, depth: 0) } }
    var rows: [Row] = []
    var shown: Set<String> = []
    for item in items {
      let parts = item.directory.split(separator: "/").map(String.init)
      for depth in parts.indices {
        let folder = parts[0...depth].joined(separator: "/")
        if shown.insert(folder).inserted { rows.append(.folder(folder, depth: depth)) }
      }
      rows.append(.file(item, depth: parts.count))
    }
    return rows
  }

  private static func state(of items: [Entry]) -> StageState {
    if items.allSatisfy({ $0.state == .all }) { return .all }
    if items.allSatisfy({ $0.state == .none }) { return .none }
    return .partial
  }

  @MainActor private static func labelColor(_ kind: ChangedFile.Kind) -> NSColor {
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

/// Zed's staged checkbox: checked, a dash when partly staged, or empty.
private struct StageBox: View {
  let state: ZedChangesList.StageState
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      Image(systemName: icon)
        .foregroundStyle(state == .none ? Color.secondary : Color.themeAccent)
        .hitTarget()
    }
    .buttonStyle(.plain)
    .accessibilityLabel(state == .all ? "Unstage" : "Stage")
    .accessibilityValue(state == .all ? "Staged" : state == .partial ? "Partly staged" : "Not staged")
    .help(AppCommand.toggleStaged.hint(state == .all ? "Unstage" : "Stage"))
  }

  private var icon: String {
    switch state {
    case .all: "checkmark.square.fill"
    case .partial: "minus.square.fill"
    case .none: "square"
    }
  }
}

private struct FolderRow: View {
  let name: String
  let depth: Int

  var body: some View {
    Label(name, systemImage: "folder")
      .labelStyle(.titleAndIcon)
      .foregroundStyle(.secondary)
      .font(.app(.body))
      .padding(.leading, CGFloat(depth) * 12 + 28)
      .selectionDisabled()
  }
}
