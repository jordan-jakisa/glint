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
  let source: DiffSource
  let lineNumberDigits: Int
  let scroller: DiffScroller
  let toggleCollapsed: (Int) -> Void
  let visibleRowsChanged: ([DiffRowID]) -> Void
  let didPaint: (DiffSource) -> Void
  /// "Stage" or "Unstage" for working-tree diffs, where changed lines can be
  /// selected and hunk headers carry an action. Nil for commits.
  var partialAction: String? = nil
  var selectionChanged: ([DiffRowID]) -> Void = { _ in }
  var hunkAction: (DiffRowID) -> Void = { _ in }

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> NSScrollView {
    let table = NSTableView()
    table.headerView = nil
    table.style = .plain
    table.intercellSpacing = .zero
    table.gridStyleMask = []
    table.selectionHighlightStyle = .regular
    table.allowsMultipleSelection = true
    table.allowsEmptySelection = true
    table.usesAutomaticRowHeights = false
    table.floatsGroupRows = true
    table.backgroundColor = .textBackgroundColor
    table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
    let column = NSTableColumn(identifier: .init("diff"))
    column.resizingMask = .autoresizingMask
    table.addTableColumn(column)

    let coordinator = context.coordinator
    table.dataSource = coordinator
    table.delegate = coordinator
    table.target = coordinator
    table.action = #selector(Coordinator.clicked(_:))

    let scrollView = NSScrollView()
    scrollView.documentView = table
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = .textBackgroundColor
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
    private var toggleCollapsed: (Int) -> Void = { _ in }
    private var visibleRowsChanged: ([DiffRowID]) -> Void = { _ in }
    private var didPaint: (DiffSource) -> Void = { _ in }
    private var partialAction: String?
    private var selectionChanged: ([DiffRowID]) -> Void = { _ in }
    private var hunkAction: (DiffRowID) -> Void = { _ in }
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
      guard let table else { return }
      let actionChanged = view.partialAction != partialAction
      partialAction = view.partialAction

      if view.rowsVersion != version || actionChanged {
        let isNewSource = view.source != source
        rows = view.rows
        version = view.rowsVersion
        source = view.source
        metrics = DiffMetrics(lineNumberDigits: view.lineNumberDigits)
        heightsWidth = -1
        // Line selections refer to the old rows; after staging, the lines
        // they pointed at are gone.
        if !table.selectedRowIndexes.isEmpty { table.deselectAll(nil) }
        table.reloadData()
        if isNewSource {
          scroll(toY: 0)
          // Runs after this pass's display commit, so it marks the frame the
          // new diff is actually in.
          let source = view.source
          DispatchQueue.main.async { [weak self] in self?.didPaint(source) }
        }
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
      cell.configure(rows[row], metrics: metrics, hunkAction: partialAction.map { "\($0) Hunk" })
      return cell
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

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
      guard partialAction != nil else { return false }
      switch rows[row].content {
      case .line(let line): return line.kind == .addition || line.kind == .deletion
      case .split(let pair):
        return pair.left?.kind == .deletion || pair.right?.kind == .addition
      default: return false
      }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
      guard let table else { return }
      selectionChanged(table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0].id : nil })
    }

    @objc func clicked(_ sender: NSTableView) {
      let row = sender.clickedRow
      guard rows.indices.contains(row) else { return }
      switch rows[row].content {
      case .fileHeader(let file, _):
        toggleCollapsed(file.id)
      case .hunkHeader where partialAction != nil:
        // Only the action label at the right edge acts; the rest of the
        // header is just a header.
        guard let event = NSApp.currentEvent else { return }
        let point = sender.convert(event.locationInWindow, from: nil)
        if point.x > sender.bounds.width - DiffRowCell.hunkActionWidth { hunkAction(rows[row].id) }
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
  static let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
  static let boldFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
  static let advance: CGFloat = ("0" as NSString).size(withAttributes: [.font: font]).width
  static let lineHeight: CGFloat = ceil(font.ascender - font.descender + font.leading)
  static let tabWidth = 4

  static let fileHeaderHeight: CGFloat = 30
  static let hunkHeaderHeight: CGFloat = 22
  static let noteHeight: CGFloat = 32
  static let verticalPadding: CGFloat = 1
  static let markerWidth: CGFloat = 16
  static let trailingPadding: CGFloat = 8

  let gutterWidth: CGFloat

  init(lineNumberDigits: Int) {
    gutterWidth = CGFloat(lineNumberDigits) * Self.advance + 12
  }

  /// Width available for code on one side of a row.
  func textWidth(rowWidth: CGFloat, split: Bool) -> CGFloat {
    if split {
      return (rowWidth - 1) / 2 - gutterWidth - Self.markerWidth - Self.trailingPadding
    }
    return rowWidth - 2 * gutterWidth - Self.markerWidth - Self.trailingPadding
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
      let lines = Self.wrappedLines(line.text, width: textWidth(rowWidth: width, split: false))
      return CGFloat(lines) * Self.lineHeight + 2 * Self.verticalPadding
    case .split(let pair):
      let width = textWidth(rowWidth: width, split: true)
      let lines = max(
        pair.left.map { Self.wrappedLines($0.text, width: width) } ?? 1,
        pair.right.map { Self.wrappedLines($0.text, width: width) } ?? 1)
      return CGFloat(lines) * Self.lineHeight + 2 * Self.verticalPadding
    }
  }

  /// How many lines `text` wraps to at `width`. Plain ASCII, the common case,
  /// is pure arithmetic. Anything else is measured, because wide characters
  /// and fallback fonts break the one-advance assumption.
  static func wrappedLines(_ text: String, width: CGFloat) -> Int {
    let perLine = max(1, Int(width / advance))
    var columns = 0
    for byte in text.utf8 {
      if byte == UInt8(ascii: "\t") {
        columns += tabWidth - columns % tabWidth
      } else if byte < 0x80 {
        columns += 1
      } else {
        return measuredLines(text, width: width)
      }
    }
    return max(1, (columns + perLine - 1) / perLine)
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
