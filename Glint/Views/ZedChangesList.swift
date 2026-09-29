import SwiftUI

/// The Changes list as Zed's git panel draws it (crates/git_ui/src/
/// git_panel.rs): a View Diff row with the total line counts, then
/// collapsible Conflicts / Tracked / Untracked sections. Each row is a status
/// icon, the name, the folder dimmed, the file's `+N −N`, and a staged
/// checkbox on the right. Rows are 28 pt, as in Zed (1.75 rem), with Zed's
/// selection tint. Used in Style Zed.
struct ZedChangesList: View {
  @Bindable var session: RepositorySession
  @AppStorage("gitPanelTree") private var isTree = false
  @AppStorage("gitPanelSortByName") private var sortByName = false
  @AppStorage("gitPanelGroupBy") private var groupBy = Grouping.trackedUntracked

  /// Zed's Group By.
  enum Grouping: String {
    case none, trackedUntracked, stagedUnstaged
  }
  @State private var collapsed: Set<String> = []

  var body: some View {
    VStack(spacing: 0) {
      header
      Hairline()
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(spacing: 0) {
            section("Conflicts", entries.filter { $0.kind == .conflicted })
            switch groupBy {
            case .none:
              section("Changes", entries.filter { $0.kind != .conflicted })
            case .trackedUntracked:
              section("Tracked", entries.filter { $0.kind != .conflicted && $0.kind != .untracked })
              section("Untracked", entries.filter { $0.kind == .untracked })
            case .stagedUnstaged:
              section("Staged", entries.filter { $0.kind != .conflicted && $0.state == .all })
              section("Unstaged", entries.filter { $0.kind != .conflicted && $0.state != .all })
            }
          }
          .padding(.vertical, 2)
        }
        .onChange(of: session.selectedChange) { _, selection in
          if let path = selection?.path { proxy.scrollTo(path) }
        }
      }
    }
  }

  // MARK: Header

  /// Zed's changes header: View Diff with the totals, view options, and a
  /// Stage All split button.
  private var header: some View {
    HStack(spacing: 6) {
      Button {
        session.selectedChange = ChangeSelection(staged: false, path: nil)
      } label: {
        HStack(spacing: 4) {
          Text("\u{00B1} View Diff")
          LineStatLabel(stat: totals)
        }
      }
      .buttonStyle(.plain)
      .help("Every change in one diff")
      Spacer()
      // Zed's View Options: View, Sort By, Group By.
      Menu {
        Picker("View", selection: $isTree) {
          Text("List").tag(false)
          Text("Tree").tag(true)
        }
        .pickerStyle(.inline)
        Picker("Sort By", selection: $sortByName) {
          Text("Path").tag(false)
          Text("Name").tag(true)
        }
        .pickerStyle(.inline)
        Picker("Group By", selection: $groupBy) {
          Text("None").tag(Grouping.none)
          Text("Tracked & Untracked").tag(Grouping.trackedUntracked)
          Text("Staged & Unstaged").tag(Grouping.stagedUnstaged)
        }
        .pickerStyle(.inline)
      } label: {
        Image(systemName: "slider.horizontal.3")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
      .tint(.secondary)
      .help("View options")
      Menu {
        Button("Stage All", action: session.stageAll)
        Button("Unstage All", action: session.unstageAll)
        Divider()
        Button("Restore All Changes\u{2026}") {
          session.requestDiscard(session.status.unstaged.filter { $0.kind != .untracked }.map(\.path))
        }
        Button("Trash Untracked Files\u{2026}") {
          session.requestDiscard(session.status.unstaged.filter { $0.kind == .untracked }.map(\.path))
        }
        Divider()
        Button("Stash All") { session.requestStash(.all) }
        Button("Stash Tracked") { session.requestStash(.tracked) }
        Button("Stash Staged") { session.requestStash(.staged) }
        Button("Stash Pop") { session.popLatestStash() }
        Button("View Stash") { session.isStashPickerShown = true }
      } label: {
        Text(allStaged ? "Unstage All" : "Stage All")
      } primaryAction: {
        allStaged ? session.unstageAll() : session.stageAll()
      }
      .menuStyle(.borderedButton)
      .controlSize(.small)
      .fixedSize()
    }
    .font(.app(.callout))
    .padding(.leading, 10)
    .padding(.trailing, 4)
    .frame(height: 28)
  }

  // MARK: Sections and rows

  @ViewBuilder private func section(_ title: String, _ items: [Entry]) -> some View {
    if !items.isEmpty {
      let isCollapsed = collapsed.contains(title)
      HStack(spacing: 4) {
        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
          .font(.app(.caption2))
          .frame(width: 12)
        Text(title).font(.app(.caption))
        Spacer()
        StageBox(state: Self.state(of: items)) { stage(items, Self.state(of: items) != .all) }
      }
      .foregroundStyle(.secondary)
      .padding(.leading, 10)
      .padding(.trailing, 4)
      .frame(height: 28)
      .contentShape(Rectangle())
      .onTapGesture {
        if isCollapsed { collapsed.remove(title) } else { collapsed.insert(title) }
      }
      if !isCollapsed {
        ForEach(rows(for: items)) { row in
          switch row {
          case .folder(let path, let depth):
            FolderRow(name: (path as NSString).lastPathComponent, depth: depth)
          case .file(let entry, let depth):
            fileRow(entry, depth: depth)
          }
        }
      }
    }
  }

  private func fileRow(_ entry: Entry, depth: Int) -> some View {
    let isSelected = session.selectedChange?.path == entry.path
    return HStack(spacing: 6) {
      HStack(spacing: 4) {
        StatusIcon(kind: entry.kind)
        Text(entry.fileName)
          .foregroundStyle(entry.kind == .deleted ? .tertiary : .primary)
          .strikethrough(entry.kind == .deleted)
          .lineLimit(1)
        if !isTree {
          Text(entry.directory)
            .foregroundStyle(entry.kind == .deleted ? .tertiary : .secondary)
            .strikethrough(entry.kind == .deleted)
            .lineLimit(1)
            .truncationMode(.head)
        }
      }
      .padding(.leading, CGFloat(depth) * 16)
      Spacer(minLength: 4)
      if let stat = session.lineStats[entry.path] {
        LineStatLabel(stat: stat).font(.app(.caption))
      }
      StageBox(state: entry.state) { session.setStaged(entry.path, entry.state != .all) }
    }
    .font(.app(.body))
    .padding(.leading, 10)
    .padding(.trailing, 4)
    .frame(height: 28)
    // Zed: the info colour at 8% behind the selected row, and a border in
    // the accent when the panel has focus.
    .background(isSelected ? Color.themeAccent.opacity(0.08) : .clear)
    .overlay {
      if isSelected { Rectangle().strokeBorder(Color.themeAccent, lineWidth: 1) }
    }
    .contentShape(Rectangle())
    .onTapGesture { session.selectedChange = ChangeSelection(staged: false, path: entry.path) }
    .id(entry.path)
    .help(entry.path)
    .contextMenu { menu(for: entry) }
  }

  /// Zed's entry menu, in Zed's order.
  @ViewBuilder private func menu(for entry: Entry) -> some View {
    Button("Open Diff") { session.selectedChange = ChangeSelection(staged: false, path: entry.path) }
    Button("View File") { session.openFile(entry.path) }
    Button("View File History") { session.showHistory(for: entry.path) }
    Divider()
    Button(entry.state == .all ? "Unstage" : "Stage") { session.setStaged(entry.path, entry.state != .all) }
    if entry.kind == .untracked {
      Button("Trash Untracked File\u{2026}") { session.requestDiscard([entry.path]) }
    } else if entry.kind != .conflicted, entry.hasUnstaged {
      Button("Restore File\u{2026}") { session.requestDiscard([entry.path]) }
    }
    Divider()
    Button("Copy Path") { session.copyAbsolutePath(entry.path) }
    Button("Copy Relative Path") { session.copyPath(entry.path) }
    if entry.kind == .untracked {
      Divider()
      Button("Add to .gitignore") { session.ignore(entry.path, privately: false) }
      Button("Add to .git/info/exclude") { session.ignore(entry.path, privately: true) }
    }
    if entry.kind != .added, entry.kind != .untracked {
      Divider()
      Button("Copy File Permalink") { session.copyFilePermalink(entry.path) }
      Button("Open File Permalink") { session.openFilePermalink(entry.path) }
    }
    Divider()
    Button("Reveal in Finder") { session.revealInFinder(entry.path) }
  }

  private func stage(_ items: [Entry], _ staged: Bool) {
    for item in items where (item.state == .all) != staged { session.setStaged(item.path, staged) }
  }

  // MARK: Model

  typealias Entry = StagingEntry

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

  /// Each path once, staged and unstaged together.
  private var entries: [Entry] {
    let entries = session.status.entries
    guard sortByName else { return entries }
    return entries.sorted { ($0.fileName, $0.path) < ($1.fileName, $1.path) }
  }

  private var totals: LineStat {
    session.lineStats.values.reduce(LineStat(added: 0, deleted: 0)) {
      LineStat(added: $0.added + $1.added, deleted: $0.deleted + $1.deleted)
    }
  }

  private var allStaged: Bool { !entries.isEmpty && entries.allSatisfy { $0.state == .all } }

  /// Flat: the files. Tree: each folder once, before its files, indented
  /// 16 pt a level, as in Zed.
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
}

/// Zed's `+N −N`, added in green and deleted in red.
struct LineStatLabel: View {
  let stat: LineStat

  var body: some View {
    HStack(spacing: 4) {
      Text("+\(stat.added)").foregroundStyle(Color(nsColor: Theme.shared.createdLabel))
      Text("\u{2212}\(stat.deleted)").foregroundStyle(Color(nsColor: Theme.shared.deletedLabel))
    }
    .monospacedDigit()
  }
}

/// Zed's git status icon: a small rounded square in the status colour, with
/// a dot for modified, a plus for added and a minus for deleted.
struct StatusIcon: View {
  let kind: ChangedFile.Kind

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 2.5).strokeBorder(color, lineWidth: 1.25)
      switch kind {
      case .added, .untracked: Image(systemName: "plus").font(.system(size: 7, weight: .bold))
      case .deleted: Image(systemName: "minus").font(.system(size: 7, weight: .bold))
      case .conflicted: Image(systemName: "exclamationmark").font(.system(size: 7, weight: .bold))
      case .renamed: Image(systemName: "arrow.right").font(.system(size: 6, weight: .bold))
      case .modified, .typeChanged: Circle().frame(width: 3.5, height: 3.5)
      }
    }
    .foregroundStyle(color)
    .frame(width: 12, height: 12)
    .accessibilityLabel(label)
  }

  private var color: Color {
    let theme = Theme.shared
    let color: NSColor =
      switch kind {
      case .added, .untracked: theme.createdLabel
      case .deleted: theme.deletedLabel
      case .modified, .typeChanged: theme.modified
      case .renamed: theme.renamed
      case .conflicted: theme.conflicted
      }
    return Color(nsColor: color)
  }

  private var label: String {
    switch kind {
    case .added: "Added"
    case .untracked: "Untracked"
    case .deleted: "Deleted"
    case .modified: "Modified"
    case .typeChanged: "Type changed"
    case .renamed: "Renamed"
    case .conflicted: "Conflicted"
    }
  }
}

/// Zed's filled checkbox: accent-filled with a check when staged, a dash
/// when partly staged, an outline when not.
private struct StageBox: View {
  let state: StageState
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      ZStack {
        RoundedRectangle(cornerRadius: 3)
          .fill(state == .none ? Color.clear : Color.themeAccent)
        RoundedRectangle(cornerRadius: 3)
          .strokeBorder(state == .none ? Color.secondary.opacity(0.6) : Color.themeAccent, lineWidth: 1)
        if state != .none {
          Image(systemName: state == .all ? "checkmark" : "minus")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.white)
        }
      }
      .frame(width: 14, height: 14)
      .hitTarget()
    }
    .buttonStyle(.plain)
    .accessibilityLabel(state == .all ? "Unstage" : "Stage")
    .accessibilityValue(state == .all ? "Staged" : state == .partial ? "Partly staged" : "Not staged")
    .help(AppCommand.toggleStaged.hint(state == .all ? "Unstage" : "Stage"))
  }
}

private struct FolderRow: View {
  let name: String
  let depth: Int

  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "folder").font(.app(.caption))
      Text(name).lineLimit(1)
      Spacer()
    }
    .foregroundStyle(.secondary)
    .font(.app(.body))
    .padding(.leading, 10 + CGFloat(depth) * 16)
    .frame(height: 28)
  }
}
