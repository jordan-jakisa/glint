import AppKit

/// Draws one diff row directly: no subviews, no Auto Layout. The table reuses
/// these as rows scroll by, so only what is on screen ever exists.
final class DiffRowCell: NSView {
  private var row: DiffRow?
  private var metrics = DiffMetrics(lineNumberDigits: 3)
  private var hunkAction: String?
  var isRowSelected = false {
    didSet { if isRowSelected != oldValue { needsDisplay = true } }
  }

  /// Faint tints, twice as strong with Increase Contrast on, so hunk headers
  /// and empty sides stay visible.
  static func tint(_ alpha: CGFloat) -> CGFloat {
    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? alpha * 2 : alpha
  }

  /// Width of the clickable "Stage Hunk" label at the right of a hunk header.
  static let hunkActionWidth: CGFloat = 110

  init(identifier: NSUserInterfaceItemIdentifier) {
    super.init(frame: .zero)
    self.identifier = identifier
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { true }

  func configure(_ row: DiffRow, metrics: DiffMetrics, hunkAction: String? = nil) {
    self.row = row
    self.metrics = metrics
    let actionChanged = self.hunkAction != hunkAction
    self.hunkAction = hunkAction
    isRowSelected = (superview as? NSTableRowView)?.isSelected ?? false
    needsDisplay = true
    if actionChanged { window?.invalidateCursorRects(for: self) }
  }

  /// The hunk action is drawn text, not a button, so it says it's clickable
  /// with the pointing hand and a tooltip.
  override func resetCursorRects() {
    removeAllToolTips()
    guard let hunkAction, case .hunkHeader = row?.content else { return }
    let action = NSRect(x: bounds.width - Self.hunkActionWidth, y: 0, width: Self.hunkActionWidth, height: bounds.height)
    addCursorRect(action, cursor: .pointingHand)
    addToolTip(action, owner: AppCommand.stagePartial.hint(hunkAction) as NSString, userData: nil)
  }

  override func draw(_ dirtyRect: NSRect) {
    NSColor.textBackgroundColor.setFill()
    bounds.fill()
    guard let row else { return }
    switch row.content {
    case .fileHeader(let file, let collapsed): drawFileHeader(file, collapsed: collapsed)
    case .hunkHeader(let hunk): drawHunkHeader(hunk)
    case .note(let text): drawNote(text)
    case .line(let line): drawUnified(line)
    case .split(let pair): drawSplit(pair)
    }
    if isRowSelected {
      Theme.shared.accentColor.withAlphaComponent(0.22).setFill()
      bounds.fill(using: .sourceOver)
      Theme.shared.accentColor.setFill()
      NSRect(x: 0, y: 0, width: 3, height: bounds.height).fill()
    }
  }

  // MARK: - Headers

  private func drawFileHeader(_ file: FileChange, collapsed: Bool) {
    NSColor.windowBackgroundColor.setFill()
    bounds.fill()
    Hairline.nsColor.setFill()
    let pixel = 1 / (window?.backingScaleFactor ?? 2)
    NSRect(x: 0, y: 0, width: bounds.width, height: pixel).fill()
    NSRect(x: 0, y: bounds.height - pixel, width: bounds.width, height: pixel).fill()

    let midY = bounds.midY
    var x: CGFloat = 12
    let chevron = NSImage(
      systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(
        .init(pointSize: 10, weight: .semibold).applying(.init(paletteColors: [.secondaryLabelColor])))
    if let chevron {
      let size = chevron.size
      chevron.draw(in: NSRect(x: x + (12 - size.width) / 2, y: midY - size.height / 2, width: size.width, height: size.height))
    }
    x += 20

    let status = StatusMark(file.status)
    let badge = NSRect(x: x, y: midY - StatusMark.size / 2, width: StatusMark.size, height: StatusMark.size)
    status.color.withAlphaComponent(StatusMark.tint).setFill()
    NSBezierPath(roundedRect: badge, xRadius: StatusMark.radius, yRadius: StatusMark.radius).fill()
    let letter = NSAttributedString(
      string: status.letter, attributes: [.font: StatusMark.font, .foregroundColor: status.color])
    let letterSize = letter.size()
    letter.draw(at: NSPoint(x: badge.midX - letterSize.width / 2, y: badge.midY - letterSize.height / 2))
    x += 24

    // Stats on the right, path fills what is left, truncated from the front
    // so the file name stays visible.
    var right = bounds.width - 12
    for (text, color) in [("-\(file.deletions)", Theme.shared.removed), ("+\(file.additions)", Theme.shared.added)] {
      guard text.dropFirst() != "0" else { continue }
      let stat = NSAttributedString(string: text, attributes: [.font: DiffMetrics.font, .foregroundColor: color])
      let size = stat.size()
      right -= size.width
      stat.draw(at: NSPoint(x: right, y: midY - size.height / 2))
      right -= 8
    }

    var title = file.path
    if let old = file.oldPath, let new = file.newPath, old != new { title = "\(old) → \(new)" }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingHead
    let path = NSAttributedString(
      string: title,
      attributes: [.font: DiffMetrics.boldFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    path.draw(
      with: NSRect(x: x, y: midY - DiffMetrics.lineHeight / 2, width: max(0, right - x - 4), height: DiffMetrics.lineHeight),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
  }

  private func drawHunkHeader(_ hunk: Hunk) {
    Theme.shared.accentColor.withAlphaComponent(Self.tint(0.08)).setFill()
    bounds.fill()
    var width = bounds.width - 24
    if let hunkAction {
      let label = NSAttributedString(
        string: hunkAction,
        attributes: [.font: AppFont.ns(size: AppFont.small, weight: .semibold), .foregroundColor: Theme.shared.accentColor])
      let size = label.size()
      label.draw(at: NSPoint(x: bounds.width - 12 - size.width, y: (bounds.height - size.height) / 2))
      width -= Self.hunkActionWidth
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingTail
    NSAttributedString(
      string: hunk.header,
      attributes: [.font: DiffMetrics.font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: paragraph]
    ).draw(
      with: NSRect(x: 12, y: (bounds.height - DiffMetrics.lineHeight) / 2, width: max(0, width), height: DiffMetrics.lineHeight),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
  }

  private func drawNote(_ text: String) {
    let note = NSAttributedString(
      string: text,
      attributes: [.font: AppFont.ns(size: AppFont.body), .foregroundColor: NSColor.secondaryLabelColor])
    note.draw(at: NSPoint(x: 16, y: (bounds.height - note.size().height) / 2))
  }

  // MARK: - Lines

  private func drawUnified(_ line: DiffLine) {
    Self.background(line.kind).setFill()
    bounds.fill()
    let gutter = metrics.gutterWidth
    Self.gutterBackground(line.kind).setFill()
    NSRect(x: 0, y: 0, width: 2 * gutter, height: bounds.height).fill()
    drawNumber(line.oldNumber, rightEdge: gutter - 6)
    drawNumber(line.newNumber, rightEdge: 2 * gutter - 6)
    drawCode(line, x: 2 * gutter, width: metrics.textWidth(rowWidth: bounds.width, split: false))
  }

  private func drawSplit(_ pair: SplitRow) {
    let half = (bounds.width - 1) / 2
    drawSide(pair.left, number: pair.left?.oldNumber, x: 0, width: half)
    Hairline.nsColor.setFill()
    NSRect(x: half, y: 0, width: 1 / (window?.backingScaleFactor ?? 2), height: bounds.height).fill()
    drawSide(pair.right, number: pair.right?.newNumber, x: half + 1, width: half)
  }

  private func drawSide(_ line: DiffLine?, number: Int?, x: CGFloat, width: CGFloat) {
    let gutter = metrics.gutterWidth
    (line.map { Self.background($0.kind) } ?? Self.emptySide).setFill()
    NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
    Self.gutterBackground(line?.kind).setFill()
    NSRect(x: x, y: 0, width: gutter, height: bounds.height).fill()
    drawNumber(number, rightEdge: x + gutter - 6)
    if let line {
      drawCode(line, x: x + gutter, width: metrics.textWidth(rowWidth: bounds.width, split: true))
    }
  }

  private func drawNumber(_ number: Int?, rightEdge: CGFloat) {
    guard let number, let context = NSGraphicsContext.current?.cgContext else { return }
    let text = String(number)
    CodeText.drawSingleLine(
      text, color: .secondaryLabelColor,
      at: NSPoint(x: rightEdge - CGFloat(text.count) * DiffMetrics.advance, y: DiffMetrics.verticalPadding),
      in: context)
  }

  private func drawCode(_ line: DiffLine, x: CGFloat, width: CGFloat) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let marker: String
    switch line.kind {
    case .addition: marker = "+"
    case .deletion: marker = "-"
    case .context, .noNewline: marker = ""
    }
    if !marker.isEmpty {
      CodeText.drawSingleLine(
        marker, color: .secondaryLabelColor,
        at: NSPoint(x: x + (DiffMetrics.markerWidth - DiffMetrics.advance) / 2, y: DiffMetrics.verticalPadding),
        in: context)
    }
    CodeText.draw(
      DiffMetrics.displayText(line.text),
      color: line.kind == .noNewline ? .secondaryLabelColor : .labelColor,
      at: NSPoint(x: x + DiffMetrics.markerWidth, y: DiffMetrics.verticalPadding),
      width: DiffMetrics.textDrawWidth(width), in: context)
  }

  // MARK: - Colors

  private static var emptySide: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(tint(0.06)) }

  private static func background(_ kind: DiffLine.Kind) -> NSColor {
    switch kind {
    case .addition: Theme.shared.added.withAlphaComponent(0.14)
    case .deletion: Theme.shared.removed.withAlphaComponent(0.14)
    case .context, .noNewline: .textBackgroundColor
    }
  }

  private static func gutterBackground(_ kind: DiffLine.Kind?) -> NSColor {
    switch kind {
    case .addition: Theme.shared.added.withAlphaComponent(0.22)
    case .deletion: Theme.shared.removed.withAlphaComponent(0.22)
    case .context, .noNewline: NSColor.secondaryLabelColor.withAlphaComponent(tint(0.05))
    case nil: NSColor.secondaryLabelColor.withAlphaComponent(tint(0.08))
    }
  }
}
