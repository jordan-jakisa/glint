import AppKit
import SwiftUI

/// The diff body, drawn by AppKit. A SwiftUI `LazyVStack` measured every row
/// on each commit switch and missed the 50 ms budget by about 2x (see
/// docs/plans/v0.1-diff-viewer.md, step 8). An `NSTableView` only asks for the
/// rows on screen, and because the font is monospaced, row heights are
/// arithmetic instead of text layout.
struct DiffTableView: NSViewRepresentable {
  let rows: [DiffRow]
  let rowsVersion: Int
  var rowsChange: RepositorySession.RowsChange = .all
  let source: DiffSource
  let lineNumberDigits: Int
  /// Your text size; a change reflows every row.
  var textSize: CGFloat = AppFont.body
  /// Bumped when the accent or diff colours change; redraws every row.
  var themeVersion = 0
  let scroller: DiffScroller
  let toggleCollapsed: (Int) -> Void
  let visibleRowsChanged: ([DiffRowID]) -> Void
  let didPaint: (DiffSource) -> Void
  /// "Stage" or "Unstage" for working-tree diffs, where changed lines can be
  /// selected and hunk headers carry an action. Nil for commits.
  var partialAction: String? = nil
  var selectionChanged: ([DiffRowID]) -> Void = { _ in }
  var hunkAction: (DiffRowID) -> Void = { _ in }
  /// Asks to throw a hunk's changes away; nil except on your unstaged
  /// working copy. Adds "Restore" beside the hunk action.
  var restoreHunk: ((DiffRowID) -> Void)? = nil
  /// Opens the line's hunk for editing; nil where the diff isn't your
  /// working copy (commits, staged changes).
  var editLines: ((DiffRowID) -> Void)? = nil
  /// Style Zed's Open File on each file header; nil where there's no file
  /// on disk to open.
  var openFile: ((String) -> Void)? = nil
  /// Who last changed a new-side line of the file at an index; nil until
  /// that file's blame is loaded (asking starts the load). Feeds the blame
  /// column and the selected line's inline blame.
  var blame: ((Int, DiffLine) -> BlameCommit?)? = nil
  /// The blame column in the gutter.
  var showsBlame = false
  /// Bumped when blame arrives; redraws the rows on screen, nothing else.
  var blameVersion = 0
  /// "Copy Permalink to Line" and "Open Permalink to Line" in the menu.
  var permalinks: DiffPermalinks? = nil

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSScrollView {
    let table = DiffTable()
    table.headerView = nil
    table.style = .plain
    table.intercellSpacing = .zero
    table.gridStyleMask = []
    table.selectionHighlightStyle = .regular
    table.allowsMultipleSelection = true
    table.allowsEmptySelection = true
    table.usesAutomaticRowHeights = false
    table.floatsGroupRows = true
    table.backgroundColor = Theme.shared.editorBackground
    table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    let column = NSTableColumn(identifier: .init("diff"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)

    let coordinator = context.coordinator
    table.dataSource = coordinator
    table.delegate = coordinator
    table.target = coordinator
    table.action = #selector(Coordinator.clicked(_:))
    table.doubleAction = #selector(Coordinator.doubleClicked(_:))
    table.coordinator = coordinator

    let scrollView = NSScrollView()
    scrollView.documentView = table
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = Theme.shared.editorBackground
    coordinator.attach(table: table, scrollView: scrollView)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.update(from: self)
  }

  @MainActor
  final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private weak var table: NSTableView?
    private weak var scrollView: NSScrollView?
    private var rows: [DiffRow] = []
    private var version = -1
    private var source: DiffSource?
    private var metrics = DiffMetrics(lineNumberDigits: 3)
    private var heights: [CGFloat] = []
    private var heightsWidth: CGFloat = -1
    private var textSize: CGFloat = AppFont.body
    private var themeVersion = 0
    private var toggleCollapsed: (Int) -> Void = { _ in }
    private var visibleRowsChanged: ([DiffRowID]) -> Void = { _ in }
    private var didPaint: (DiffSource) -> Void = { _ in }
    private var partialAction: String?
    private var selectionChanged: ([DiffRowID]) -> Void = { _ in }
    private var editLines: ((DiffRowID) -> Void)?
    private var openFile: ((String) -> Void)?
    private var hunkAction: (DiffRowID) -> Void = { _ in }
    private var blame: ((Int, DiffLine) -> BlameCommit?)?
    private var showsBlame = false
    private var blameVersion = 0
    private(set) var permalinks: DiffPermalinks?
    /// The one selected line, which shows its blame inline; nil when none
    /// or several are selected.
    private var inlineRow: Int?
    private var restoreHunk: ((DiffRowID) -> Void)?
    private var observers: [NSObjectProtocol] = []

    func attach(table: NSTableView, scrollView: NSScrollView) {
      self.table = table
      self.scrollView = scrollView
      let clip = scrollView.contentView
      clip.postsBoundsChangedNotifications = true
      table.postsFrameChangedNotifications = true
      let center = NotificationCenter.default
      observers = [
        center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) {
          [weak self] _ in MainActor.assumeIsolated { self?.reportVisibleRows() }
        },
        center.addObserver(forName: NSView.frameDidChangeNotification, object: table, queue: .main) {
          [weak self] _ in MainActor.assumeIsolated { self?.widthMayHaveChanged() }
        },
      ]
    }

    func update(from view: DiffTableView) {
      toggleCollapsed = view.toggleCollapsed
      visibleRowsChanged = view.visibleRowsChanged
      didPaint = view.didPaint
      selectionChanged = view.selectionChanged
      hunkAction = view.hunkAction
      editLines = view.editLines
      openFile = view.openFile
      blame = view.blame
      permalinks = view.permalinks
      let restoreChanged = (view.restoreHunk != nil) != (restoreHunk != nil)
      restoreHunk = view.restoreHunk
      guard let table else { return }
      let actionChanged = view.partialAction != partialAction || restoreChanged
      partialAction = view.partialAction
      // Showing blame narrows the code, so it reflows like a size change.
      let sizeChanged =
        view.textSize != textSize || view.themeVersion != themeVersion || view.showsBlame != showsBlame
      textSize = view.textSize
      themeVersion = view.themeVersion
      // Style Zed swaps the editor colour; the table and its scroll view
      // paint it behind the rows.
      table.backgroundColor = Theme.shared.editorBackground
      scrollView?.backgroundColor = Theme.shared.editorBackground
      showsBlame = view.showsBlame
      let blameArrived = view.blameVersion != blameVersion
      blameVersion = view.blameVersion

      if view.rowsVersion != version, !actionChanged, !sizeChanged, view.source == source,
        case .file(let file) = view.rowsChange,
        DiffMetrics(lineNumberDigits: view.lineNumberDigits, showsBlame: showsBlame).sameWidths(as: metrics)
      {
        // Collapsing or expanding one file: swap only its rows. A full reload
        // rebuilt every visible row for this and missed the frame budget.
        let body = { (rows: [DiffRow]) in rows.indices.filter { rows[$0].id.file == file && rows[$0].id != .file(file) } }
        let removed = body(rows)
        let old = rows
        rows = view.rows
        version = view.rowsVersion
        heightsWidth = -1
        let inserted = body(rows)
        table.beginUpdates()
        if !removed.isEmpty { table.removeRows(at: IndexSet(removed), withAnimation: []) }
        if !inserted.isEmpty { table.insertRows(at: IndexSet(inserted), withAnimation: []) }
        if let header = old.firstIndex(where: { $0.id == .file(file) }) {
          table.reloadData(forRowIndexes: IndexSet(integer: header), columnIndexes: IndexSet(integer: 0))
        }
        table.endUpdates()
        syncInlineRow()
      } else if view.rowsVersion != version || actionChanged || sizeChanged {
        let isNewSource = view.source != source
        // Only the look changed (text size, colours): same rows, new heights.
        let lookOnly = sizeChanged && view.rowsVersion == version && !actionChanged && !isNewSource
        let topRow = table.rows(in: table.visibleRect).location
        let anchor = lookOnly && topRow < rows.count ? rows[topRow].id : nil
        let selection = table.selectedRowIndexes
        rows = view.rows
        version = view.rowsVersion
        source = view.source
        metrics = DiffMetrics(lineNumberDigits: view.lineNumberDigits, showsBlame: showsBlame)
        heightsWidth = -1
        // Line selections refer to the old rows; after staging, the lines
        // they pointed at are gone. A look change keeps them.
        if !lookOnly, !table.selectedRowIndexes.isEmpty { table.deselectAll(nil) }
        inlineRow = nil
        table.reloadData()
        if lookOnly {
          table.selectRowIndexes(selection, byExtendingSelection: false)
          syncInlineRow()
          // Keep the line you were reading at the top, not the pixel offset.
          // After this pass: the table re-tiles to its new height first and
          // would otherwise clamp the scroll back.
          if let anchor { DispatchQueue.main.async { [weak self] in self?.scroll(to: anchor) } }
        }
        if isNewSource {
          scroll(toY: 0)
          // Runs after this pass's display commit, so it marks the frame the
          // new diff is actually in.
          let source = view.source
          DispatchQueue.main.async { [weak self] in self?.didPaint(source) }
        }
      } else if blameArrived {
        // Blame for a file came in: fill in the rows on screen, no reload.
        refreshBlame(in: visibleRowIndexes())
      }

      view.scroller.perform = { [weak self] target, rowsVersion in
        guard let self, rowsVersion == self.version else { return false }
        self.scroll(to: target)
        return true
      }
      if let pending = view.scroller.takePending(for: version) { scroll(to: pending) }
    }

    private func scroll(to target: DiffRowID) {
      guard let table, let index = index(of: target) else { return }
      scroll(toY: table.rect(ofRow: index).minY)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
      let width = tableView.bounds.width
      if width != heightsWidth || heights.count != rows.count {
        heights = rows.map { metrics.height(of: $0, width: width) }
        heightsWidth = width
      }
      return heights[row]
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
      if case .fileHeader = rows[row].content { return true }
      return false
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
      let identifier = NSUserInterfaceItemIdentifier("DiffRowCell")
      let cell =
        tableView.makeView(withIdentifier: identifier, owner: nil) as? DiffRowCell
        ?? DiffRowCell(identifier: identifier)
      let (column, inline) = blame(forRow: row)
      cell.configure(
        rows[row], metrics: metrics, hunkAction: hunkActionTitle(for: rows[row]), blame: column, inlineBlame: inline,
        restoreAction: restoreHunk != nil && !rows[row].fileIsStaged, openFile: openFile != nil)
      return cell
    }

    // MARK: Blame

    /// The new side of a line row: the line blame describes. Removed lines
    /// have none.
    private func newSideLine(_ row: Int) -> DiffLine? {
      let line: DiffLine?
      switch rows[row].content {
      case .line(let unified): line = unified
      case .split(let pair): line = pair.right
      default: line = nil
      }
      guard let line, line.kind == .context || line.kind == .addition else { return nil }
      return line
    }

    /// Blame for the column (when shown) and for the inline note (on the one
    /// selected line). Only asks for rows that draw it, so only files on
    /// screen get blamed.
    private func blame(forRow row: Int) -> (column: BlameCommit?, inline: BlameCommit?) {
      let isInline = row == inlineRow
      guard let blame, showsBlame || isInline, rows.indices.contains(row), let line = newSideLine(row) else {
        return (nil, nil)
      }
      let commit = blame(rows[row].id.file, line)
      return (showsBlame ? commit : nil, isInline ? commit : nil)
    }

    private func refreshBlame(in indexes: IndexSet) {
      guard let table else { return }
      for index in indexes where rows.indices.contains(index) {
        guard let cell = table.view(atColumn: 0, row: index, makeIfNecessary: false) as? DiffRowCell else { continue }
        let (column, inline) = blame(forRow: index)
        cell.setBlame(column, inline: inline)
      }
    }

    private func visibleRowIndexes() -> IndexSet {
      guard let table else { return [] }
      let range = table.rows(in: table.visibleRect)
      guard range.location != NSNotFound, range.length > 0 else { return [] }
      return IndexSet(integersIn: range.location..<(range.location + range.length))
    }

    /// Moves the inline blame to the one selected line, if there is one.
    private func syncInlineRow() {
      guard let table else { return }
      let selected = table.selectedRowIndexes
      let row = selected.count == 1 ? selected.first : nil
      guard row != inlineRow else { return }
      let old = inlineRow
      inlineRow = row
      refreshBlame(in: IndexSet([old, row].compactMap { $0 }))
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
      // Reused like cells. Building a fresh row view per row made every jump
      // to an unseen part of the diff pay for a screenful of new views.
      let identifier = NSUserInterfaceItemIdentifier("PlainRowView")
      if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? PlainRowView {
        return reused
      }
      let rowView = PlainRowView()
      rowView.identifier = identifier
      return rowView
    }

    /// Any line can be selected, to copy it; only changed lines count
    /// towards staging.
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
      switch rows[row].content {
      case .line(let line): line.kind != .noNewline
      case .split: true
      default: false
      }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
      guard let table else { return }
      syncInlineRow()
      guard partialAction != nil else { return selectionChanged([]) }
      selectionChanged(
        table.selectedRowIndexes.compactMap { index in
          guard rows.indices.contains(index), Self.isChange(rows[index]) else { return nil }
          return rows[index].id
        })
    }

    private static func isChange(_ row: DiffRow) -> Bool {
      switch row.content {
      case .line(let line): line.kind == .addition || line.kind == .deletion
      case .split(let pair): pair.left?.kind == .deletion || pair.right?.kind == .addition
      default: false
      }
    }

    /// "Stage Hunk" or "Unstage Hunk", where hunks can be staged.
    var hunkActionTitle: String? { partialAction.map { "\($0) Hunk" } }

    /// A fully staged file's hunks unstage, whatever the diff's side.
    func hunkActionTitle(for row: DiffRow) -> String? {
      guard partialAction != nil else { return nil }
      return row.fileIsStaged ? "Unstage Hunk" : hunkActionTitle
    }
    var canRestoreHunks: Bool { restoreHunk != nil }

    /// The hunk a row belongs to, for the right-click hunk actions.
    func hunk(at index: Int) -> DiffRowID? {
      guard partialAction != nil, rows.indices.contains(index) else { return nil }
      switch rows[index].content {
      case .hunkHeader, .line, .split: return .hunk(rows[index].id.file, rows[index].id.hunk)
      default: return nil
      }
    }

    func stageHunkAt(row index: Int) {
      guard let hunk = hunk(at: index) else { return }
      hunkAction(hunk)
    }

    func restoreHunkAt(row index: Int) {
      guard let hunk = hunk(at: index) else { return }
      restoreHunk?(hunk)
    }

    // MARK: Copy and edit

    /// The selected lines as plain text: the new side where there is one, so
    /// what you paste is the code as it stands.
    func copySelection() {
      guard let table else { return }
      let text = table.selectedRowIndexes.compactMap { index -> String? in
        guard rows.indices.contains(index) else { return nil }
        switch rows[index].content {
        case .line(let line): return line.kind == .noNewline ? nil : line.text
        case .split(let pair): return (pair.right ?? pair.left)?.text
        default: return nil
        }
      }
      guard !text.isEmpty else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(text.joined(separator: "\n"), forType: .string)
    }

    var canCopy: Bool { !(table?.selectedRowIndexes.isEmpty ?? true) }

    /// The line row to edit: the clicked one, else the first selected.
    func editableRow(at index: Int) -> DiffRowID? {
      guard editLines != nil, rows.indices.contains(index) else { return nil }
      switch rows[index].content {
      case .line, .split: return rows[index].id
      default: return nil
      }
    }

    /// The line a permalink can point at: the clicked line row, if the
    /// session can link to it.
    func linkableRow(at index: Int) -> DiffRowID? {
      guard let permalinks, rows.indices.contains(index) else { return nil }
      switch rows[index].content {
      case .line(let line) where line.kind == .noNewline: return nil
      case .line, .split: return permalinks.canLink(rows[index].id) ? rows[index].id : nil
      default: return nil
      }
    }

    func edit(row index: Int) {
      guard let id = editableRow(at: index) else { return }
      editLines?(id)
    }

    @objc func doubleClicked(_ sender: NSTableView) {
      edit(row: sender.clickedRow)
    }

    @objc func clicked(_ sender: NSTableView) {
      let row = sender.clickedRow
      guard rows.indices.contains(row) else { return }
      switch rows[row].content {
      case .fileHeader(let file, _):
        // Style Zed: Open File at the right edge opens it; the rest of the
        // header folds the file, as everywhere.
        if Theme.shared.isZed, let openFile, let path = file.newPath, file.status != .deleted,
          let point = NSApp.currentEvent.map({ sender.convert($0.locationInWindow, from: nil) }),
          point.x > sender.bounds.width - DiffRowCell.openFileWidth
        {
          openFile(path)
        } else {
          toggleCollapsed(file.id)
        }
      // Style Zed: the hovered line's hunk actions.
      case .line, .split where Theme.shared.isZed && partialAction != nil:
        guard let event = NSApp.currentEvent else { return }
        let point = sender.convert(event.locationInWindow, from: nil)
        let zones = DiffRowCell.hunkActionZones(
          rowWidth: sender.bounds.width, action: hunkActionTitle(for: rows[row]),
          restore: canRestoreHunks && !rows[row].fileIsStaged)
        switch zones.first(where: { $0.hit.contains(point.x) })?.kind {
        case .primary: hunkAction(rows[row].id)
        case .restore: restoreHunk?(rows[row].id)
        case nil: break
        }
      case .hunkHeader where partialAction != nil:
        // Only the action label at the right edge acts; the rest of the
        // header is just a header.
        guard let event = NSApp.currentEvent else { return }
        let point = sender.convert(event.locationInWindow, from: nil)
        let zones = DiffRowCell.hunkActionZones(
          rowWidth: sender.bounds.width, action: hunkActionTitle(for: rows[row]),
          restore: canRestoreHunks && !rows[row].fileIsStaged)
        switch zones.first(where: { $0.hit.contains(point.x) })?.kind {
        case .primary: hunkAction(rows[row].id)
        case .restore: restoreHunk?(rows[row].id)
        case nil: break
        }
      default:
        break
      }
    }

    // MARK: Scrolling

    private func scroll(toY y: CGFloat) {
      guard let scrollView else { return }
      let clip = scrollView.contentView
      let target = clip.constrainBoundsRect(NSRect(origin: NSPoint(x: 0, y: y), size: clip.bounds.size))
      clip.scroll(to: target.origin)
      scrollView.reflectScrolledClipView(clip)
    }

    private func reportVisibleRows() {
      guard let table, !rows.isEmpty else { return }
      let range = table.rows(in: table.visibleRect)
      guard range.location != NSNotFound, range.location < rows.count else { return }
      visibleRowsChanged([rows[range.location].id])
    }

    private func widthMayHaveChanged() {
      guard let table, table.bounds.width != heightsWidth, !rows.isEmpty else { return }
      // Heights depend on how many characters fit per line. Recompute only
      // when that count changes, which is every few points of resizing.
      if heightsWidth > 0, metrics.columns(forWidth: table.bounds.width) == metrics.columns(forWidth: heightsWidth) {
        heightsWidth = table.bounds.width
        return
      }
      heightsWidth = -1
      table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
    }

    /// Rows are sorted by id, so a binary search finds any row.
    private func index(of id: DiffRowID) -> Int? {
      var low = 0
      var high = rows.count - 1
      while low <= high {
        let mid = (low + high) / 2
        if rows[mid].id == id { return mid }
        if rows[mid].id < id { low = mid + 1 } else { high = mid - 1 }
      }
      return nil
    }
  }
}

/// The diff's table: ⌘C copies the selected lines, and right-click offers
/// Copy, the clicked hunk's actions, Edit on your working copy, and
/// permalinks to the line.
final class DiffTable: NSTableView {
  weak var coordinator: DiffTableView.Coordinator?

  @objc func copy(_ sender: Any?) {
    coordinator?.copySelection()
  }

  override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
    if item.action == #selector(copy(_:)) { return coordinator?.canCopy ?? false }
    return super.validateUserInterfaceItem(item)
  }

  override func menu(for event: NSEvent) -> NSMenu? {
    let row = self.row(at: convert(event.locationInWindow, from: nil))
    guard row >= 0, let coordinator else { return nil }
    // Right-clicking outside the selection selects that line, as lists do.
    if !selectedRowIndexes.contains(row), coordinator.tableView(self, shouldSelectRow: row) {
      selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }
    let menu = NSMenu()
    let copy = menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
    copy.target = self
    if coordinator.editableRow(at: row) != nil {
      let edit = menu.addItem(withTitle: "Edit These Lines\u{2026}", action: #selector(editClicked(_:)), keyEquivalent: "")
      edit.target = self
      edit.tag = row
    }
    if coordinator.hunk(at: row) != nil, let title = coordinator.hunkActionTitle {
      menu.addItem(.separator())
      let stage = menu.addItem(withTitle: title, action: #selector(stageHunkClicked(_:)), keyEquivalent: "")
      stage.target = self
      stage.tag = row
      if coordinator.canRestoreHunks {
        let restore = menu.addItem(
          withTitle: "Restore Hunk\u{2026}", action: #selector(restoreHunkClicked(_:)), keyEquivalent: "")
        restore.target = self
        restore.tag = row
      }
    }
    if let permalinks = coordinator.permalinks, let line = coordinator.linkableRow(at: row) {
      menu.addItem(.separator())
      let note = permalinks.note(line)
      for (title, action) in [
        ("Copy Permalink to Line", #selector(copyPermalinkClicked(_:))),
        ("Open Permalink to Line", #selector(openPermalinkClicked(_:))),
      ] {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.tag = row
        item.toolTip = note
      }
    }
    return menu
  }

  @objc private func stageHunkClicked(_ sender: NSMenuItem) {
    coordinator?.stageHunkAt(row: sender.tag)
  }

  @objc private func restoreHunkClicked(_ sender: NSMenuItem) {
    coordinator?.restoreHunkAt(row: sender.tag)
  }

  @objc private func editClicked(_ sender: NSMenuItem) {
    coordinator?.edit(row: sender.tag)
  }

  @objc private func copyPermalinkClicked(_ sender: NSMenuItem) {
    guard let coordinator, let line = coordinator.linkableRow(at: sender.tag) else { return }
    coordinator.permalinks?.copy(line)
  }

  @objc private func openPermalinkClicked(_ sender: NSMenuItem) {
    guard let coordinator, let line = coordinator.linkableRow(at: sender.tag) else { return }
    coordinator.permalinks?.open(line)
  }
}

/// Links to a diff line on the remote's site, from the session.
struct DiffPermalinks {
  let canLink: (DiffRowID) -> Bool
  let copy: (DiffRowID) -> Void
  let open: (DiffRowID) -> Void
  /// A caveat for the menu item's tooltip, like a line that isn't committed.
  let note: (DiffRowID) -> String?
}

/// Carries keyboard jumps from the session to the table directly. A jump that
/// arrives before the table has the matching rows (say, it just expanded a
/// collapsed file) waits here until the table reloads.
@MainActor
final class DiffScroller {
  fileprivate var perform: ((DiffRowID, Int) -> Bool)?
  private var pending: (target: DiffRowID, rowsVersion: Int)?

  func scroll(to target: DiffRowID, rowsVersion: Int) {
    if perform?(target, rowsVersion) == true {
      pending = nil
    } else {
      pending = (target, rowsVersion)
    }
  }

  fileprivate func takePending(for rowsVersion: Int) -> DiffRowID? {
    guard let pending, pending.rowsVersion == rowsVersion else { return nil }
    self.pending = nil
    return pending.target
  }
}

/// No selection or group-row styling: every row draws its own background.
private final class PlainRowView: NSTableRowView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    // One layer per row, with the cell drawn into it, instead of a layer for
    // the row and another for its cell: half the layers to commit per frame.
    wantsLayer = true
    canDrawSubviewsIntoLayer = true
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override func drawBackground(in dirtyRect: NSRect) {}
  override func drawSelection(in dirtyRect: NSRect) {}

  /// Cells draw their own selection tint; tell them when it changes.
  override var isSelected: Bool {
    didSet {
      guard isSelected != oldValue else { return }
      for case let cell as DiffRowCell in subviews { cell.isRowSelected = isSelected }
    }
  }
}

// MARK: - Metrics

/// Sizes for the monospaced diff text. With one font and one advance width,
/// the number of wrapped lines is `columns / columnsPerLine`, no text layout
/// needed.
@MainActor
struct DiffMetrics {
  /// Measured once per text size; row heights ask for these on every row.
  private struct Measures {
    let size: CGFloat
    let font: NSFont
    let boldFont: NSFont
    let advance: CGFloat
    let lineHeight: CGFloat
    let smallFont: NSFont
    let smallAdvance: CGFloat

    init(size: CGFloat) {
      self.size = size
      font = AppFont.ns(size: size)
      smallFont = AppFont.ns(size: max(size - 2, 8))
      smallAdvance = ("0" as NSString).size(withAttributes: [.font: smallFont]).width
      boldFont = AppFont.ns(size: size, weight: .semibold)
      advance = ("0" as NSString).size(withAttributes: [.font: font]).width
      lineHeight = ceil(font.ascender - font.descender + font.leading)
    }
  }

  private static var measured = Measures(size: AppFont.codeBody)
  private static var measures: Measures {
    if measured.size != AppFont.codeBody { measured = Measures(size: AppFont.codeBody) }
    return measured
  }

  static var font: NSFont { measures.font }
  static var boldFont: NSFont { measures.boldFont }
  static var advance: CGFloat { measures.advance }
  static var lineHeight: CGFloat { measures.lineHeight }
  /// The blame column's font: the code font, a size down.
  static var smallFont: NSFont { measures.smallFont }
  static var smallAdvance: CGFloat { measures.smallAdvance }
  static let tabWidth = 4

  static var fileHeaderHeight: CGFloat { lineHeight + 14 }
  /// Style Zed shows no @@ line, only the hunk's actions in a thin row.
  /// Style Zed shows no hunk row, only a small gap; the actions appear on
  /// the line under the mouse.
  static var hunkHeaderHeight: CGFloat { Theme.shared.isZed ? 6 : lineHeight + 6 }
  static var noteHeight: CGFloat { lineHeight + 16 }
  static let verticalPadding: CGFloat = 1
  static let markerWidth: CGFloat = 16
  static let trailingPadding: CGFloat = 8

  let gutterWidth: CGFloat
  /// The blame column at the left of line rows; zero when blame is off.
  let blameWidth: CGFloat

  /// Blame reads "a1b2c3d Jordan   13 days ago": an id, a short name, a date.
  static let blameIDColumns = 7
  static let blameNameColumns = 8
  static var blameColumns: Int { blameIDColumns + 1 + blameNameColumns + 1 + BlameDate.maxLength }
  static let blamePadding: CGFloat = 8

  init(lineNumberDigits: Int, showsBlame: Bool = false) {
    gutterWidth = CGFloat(lineNumberDigits) * Self.advance + 12
    blameWidth = showsBlame ? CGFloat(Self.blameColumns) * Self.smallAdvance + 2 * Self.blamePadding : 0
  }

  /// Whether rows lay out the same with these metrics as with `other`.
  func sameWidths(as other: DiffMetrics) -> Bool {
    gutterWidth == other.gutterWidth && blameWidth == other.blameWidth
  }

  /// Width available for code on one side of a row.
  func textWidth(rowWidth: CGFloat, split: Bool) -> CGFloat {
    if split {
      return (rowWidth - blameWidth - 1) / 2 - gutterWidth - Self.markerWidth - Self.trailingPadding
    }
    // Style Zed has one number column in unified view, the new side's.
    let gutters: CGFloat = Theme.shared.isZed ? 1 : 2
    return rowWidth - blameWidth - gutters * gutterWidth - Self.markerWidth - Self.trailingPadding
  }

  func columns(forWidth width: CGFloat) -> Int {
    let unified = Int(textWidth(rowWidth: width, split: false) / Self.advance)
    let split = Int(textWidth(rowWidth: width, split: true) / Self.advance)
    return unified &* 10_000 &+ split
  }

  func height(of row: DiffRow, width: CGFloat) -> CGFloat {
    switch row.content {
    case .fileHeader: return Self.fileHeaderHeight
    case .hunkHeader: return Self.hunkHeaderHeight
    case .note: return Self.noteHeight
    case .line(let line):
      let lines = Self.wrappedLines(line, width: textWidth(rowWidth: width, split: false))
      return CGFloat(lines) * Self.lineHeight + 2 * Self.verticalPadding
    case .split(let pair):
      let width = textWidth(rowWidth: width, split: true)
      let lines = max(
        pair.left.map { Self.wrappedLines($0, width: width) } ?? 1,
        pair.right.map { Self.wrappedLines($0, width: width) } ?? 1)
      return CGFloat(lines) * Self.lineHeight + 2 * Self.verticalPadding
    }
  }

  /// How many lines `text` wraps to at `width`. Plain ASCII, the common case,
  /// is pure arithmetic. Anything else is measured, because wide characters
  /// and fallback fonts break the one-advance assumption.
  static func wrappedLines(_ line: DiffLine, width: CGFloat) -> Int {
    guard line.columns >= 0 else { return measuredLines(line.text, width: width) }
    let perLine = max(1, Int(width / advance))
    return max(1, (line.columns + perLine - 1) / perLine)
  }

  private static func measuredLines(_ text: String, width: CGFloat) -> Int {
    CodeText.lineCount(displayText(text), width: textDrawWidth(width))
  }

  /// Width handed to the text system. A whole number of columns plus a sliver,
  /// so it wraps exactly where `wrappedLines` predicts.
  static func textDrawWidth(_ width: CGFloat) -> CGFloat {
    CGFloat(max(1, Int(width / advance))) * advance + 0.5
  }

  /// Tabs expanded to spaces, so tab stops match the column arithmetic.
  static func displayText(_ text: String) -> String {
    guard text.utf8.contains(UInt8(ascii: "\t")) else { return text }
    var result = ""
    var column = 0
    for character in text {
      if character == "\t" {
        let spaces = tabWidth - column % tabWidth
        result.append(String(repeating: " ", count: spaces))
        column += spaces
      } else {
        result.append(character)
        column += 1
      }
    }
    return result
  }

}
