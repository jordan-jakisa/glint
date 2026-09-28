import AppKit

/// Draws one diff row directly: no subviews, no Auto Layout. The table reuses
/// these as rows scroll by, so only what is on screen ever exists.
final class DiffRowCell: NSView, NSViewToolTipOwner {
  private var row: DiffRow?
  private var metrics = DiffMetrics(lineNumberDigits: 3)
  private var hunkAction: String?
  /// Style Zed: whether file headers offer Open File.
  private var openFile = false
  /// The new-side line's blame, for the gutter column; nil until loaded.
  private var blame: BlameCommit?
  /// Set on the one selected line: its blame, drawn after the code.
  private var inlineBlame: BlameCommit?
  private var restoreAction = false
  var isRowSelected = false {
    didSet { if isRowSelected != oldValue { needsDisplay = true } }
  }

  /// Faint tints, twice as strong with Increase Contrast on, so hunk headers
  /// and empty sides stay visible.
  static func tint(_ alpha: CGFloat) -> CGFloat {
    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? alpha * 2 : alpha
  }

  /// A clickable label at the right of a hunk header: "Stage Hunk" (or
  /// "Unstage Hunk") at the edge, and "Restore" before it on your working
  /// copy.
  struct HunkActionZone {
    enum Kind { case primary, restore }
    let kind: Kind
    let label: String
    /// Where the label is drawn, and its wider hit area.
    let labelX: CGFloat
    let hit: ClosedRange<CGFloat>
  }

  static var hunkActionFont: NSFont { AppFont.nsSans(size: AppFont.small) }

  /// The hunk header's actions, right to left. The table's click handling
  /// uses these too, so what you see is what you hit.
  static func hunkActionZones(rowWidth: CGFloat, action: String?, restore: Bool) -> [HunkActionZone] {
    guard let action else { return [] }
    let font = hunkActionFont
    func width(_ text: String) -> CGFloat {
      ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
    let primaryX = rowWidth - 12 - width(action)
    var zones = [HunkActionZone(kind: .primary, label: action, labelX: primaryX, hit: (primaryX - 8)...rowWidth)]
    if restore {
      let label = "Restore"
      let x = primaryX - 20 - width(label)
      zones.append(HunkActionZone(kind: .restore, label: label, labelX: x, hit: (x - 8)...(primaryX - 8)))
    }
    return zones
  }

  init(identifier: NSUserInterfaceItemIdentifier) {
    super.init(frame: .zero)
    self.identifier = identifier
  }

  required init?(coder: NSCoder) { fatalError("not used") }

  override var isFlipped: Bool { true }
  override var isOpaque: Bool { true }

  // MARK: Hover (Style Zed)

  /// Style Zed shows a hunk's actions on the line under the mouse, as Zed
  /// does, instead of on a row above the hunk.
  private var isHovered = false {
    didSet {
      guard isHovered != oldValue else { return }
      needsDisplay = true
      window?.invalidateCursorRects(for: self)
    }
  }

  /// Lines show hover actions only in Style Zed, where hunk rows carry none.
  var showsHoverActions: Bool {
    guard Theme.shared.isZed, hunkAction != nil else { return false }
    switch row?.content {
    case .line, .split: return true
    default: return false
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    trackingAreas.forEach(removeTrackingArea)
    addTrackingArea(
      NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
  }

  override func mouseEntered(with event: NSEvent) { isHovered = true }
  override func mouseExited(with event: NSEvent) { isHovered = false }

  func configure(
    _ row: DiffRow, metrics: DiffMetrics, hunkAction: String? = nil, blame: BlameCommit? = nil,
    inlineBlame: BlameCommit? = nil, restoreAction: Bool = false, openFile: Bool = false
  ) {
    self.row = row
    self.openFile = openFile
    isHovered = false
    let blameResized = self.metrics.blameWidth != metrics.blameWidth
    self.metrics = metrics
    let actionChanged = self.hunkAction != hunkAction || self.restoreAction != restoreAction
    self.hunkAction = hunkAction
    self.blame = blame
    self.inlineBlame = inlineBlame
    self.restoreAction = restoreAction
    isRowSelected = (superview as? NSTableRowView)?.isSelected ?? false
    needsDisplay = true
    if actionChanged || blameResized { window?.invalidateCursorRects(for: self) }
  }

  /// Blame arrived, or the selection moved: redraw only if it changed.
  func setBlame(_ blame: BlameCommit?, inline: BlameCommit?) {
    guard blame != self.blame || inline != inlineBlame else { return }
    self.blame = blame
    inlineBlame = inline
    needsDisplay = true
  }

  /// The hunk action is drawn text, not a button, so it says it's clickable
  /// with the pointing hand and a tooltip. The blame column's tooltip is
  /// asked for on hover, so it follows the cell as it's reused.
  override func resetCursorRects() {
    removeAllToolTips()
    if metrics.blameWidth > 0 {
      // Taller than any row, so it covers wrapped lines too.
      addToolTip(NSRect(x: 0, y: 0, width: metrics.blameWidth, height: 100_000), owner: self, userData: nil)
    }
    guard let hunkAction else { return }
    if case .hunkHeader = row?.content {
    } else if !(showsHoverActions && isHovered) {
      return
    }
    for zone in Self.hunkActionZones(rowWidth: bounds.width, action: hunkAction, restore: restoreAction) {
      let rect = NSRect(x: zone.hit.lowerBound, y: 0, width: zone.hit.upperBound - zone.hit.lowerBound, height: bounds.height)
      addCursorRect(rect, cursor: .pointingHand)
      let tip =
        zone.kind == .primary
        ? AppCommand.stagePartial.hint(hunkAction) : "Throw away this hunk's changes in your working copy"
      addToolTip(rect, owner: tip as NSString, userData: nil)
    }
  }

  override func draw(_ dirtyRect: NSRect) {
    Theme.shared.editorBackground.setFill()
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
    if showsHoverActions, isHovered { drawHoverActions() }
  }

  /// The hunk's Stage and Restore at the right of the hovered line, on a
  /// small panel so they read over code.
  private func drawHoverActions() {
    let zones = Self.hunkActionZones(rowWidth: bounds.width, action: hunkAction, restore: restoreAction)
    guard let leftmost = zones.last else { return }
    let height = DiffMetrics.lineHeight
    let panel = NSRect(
      x: leftmost.hit.lowerBound, y: 1, width: bounds.width - leftmost.hit.lowerBound - 4, height: height)
    let path = NSBezierPath(roundedRect: panel, xRadius: 4, yRadius: 4)
    (Theme.shared.panelBackground ?? .windowBackgroundColor).setFill()
    path.fill()
    ZedPalette.border.setStroke()
    path.lineWidth = 1 / (window?.backingScaleFactor ?? 2)
    path.stroke()
    for zone in zones {
      let color = zone.kind == .primary ? Theme.shared.accentColor : NSColor.secondaryLabelColor
      let label = NSAttributedString(string: zone.label, attributes: [.font: Self.hunkActionFont, .foregroundColor: color])
      label.draw(at: NSPoint(x: zone.labelX, y: panel.midY - label.size().height / 2))
    }
  }

  // MARK: - Headers

  /// Style Zed's "Open File" label at the right of a file header.
  static let openFileWidth: CGFloat = 96

  /// Zed's excerpt header: a rounded card with the fold chevron, the file
  /// name in its status colour and its folder dimmed, the line counts, and
  /// Open File at the right.
  private func drawZedFileHeader(_ file: FileChange, collapsed: Bool) {
    Theme.shared.editorBackground.setFill()
    bounds.fill()
    let card = bounds.insetBy(dx: 6, dy: 4)
    let path = NSBezierPath(roundedRect: card, xRadius: 6, yRadius: 6)
    (Theme.shared.panelBackground ?? .windowBackgroundColor).setFill()
    path.fill()
    ZedPalette.border.setStroke()
    path.lineWidth = 1 / (window?.backingScaleFactor ?? 2)
    path.stroke()

    let midY = card.midY
    var x = card.minX + 10
    if let chevron = NSImage(
      systemSymbolName: collapsed ? "chevron.right" : "chevron.down", accessibilityDescription: nil)?
      .withSymbolConfiguration(.init(pointSize: AppFont.small - 2, weight: .semibold).applying(.init(paletteColors: [ZedPalette.textMuted])))
    {
      chevron.draw(in: NSRect(x: x, y: midY - chevron.size.height / 2, width: chevron.size.width, height: chevron.size.height))
    }
    x += 18

    let status = StatusMark(file.status)
    let isDeleted = file.status == .deleted
    let name = ((file.newPath ?? file.oldPath ?? "") as NSString).lastPathComponent
    let folder = ((file.newPath ?? file.oldPath ?? "") as NSString).deletingLastPathComponent
    var attributes: [NSAttributedString.Key: Any] = [
      .font: DiffMetrics.boldFont, .foregroundColor: isDeleted ? ZedPalette.textPlaceholder : status.color,
    ]
    if isDeleted { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
    let title = NSMutableAttributedString(string: name, attributes: attributes)
    if !folder.isEmpty {
      title.append(
        NSAttributedString(
          string: "  " + folder + "/",
          attributes: [.font: DiffMetrics.font, .foregroundColor: ZedPalette.textMuted]))
    }
    for (text, color) in [("+\(file.additions)", Theme.shared.createdLabel), (" \u{2212}\(file.deletions)", Theme.shared.deletedLabel)] {
      title.append(NSAttributedString(string: text == "+\(file.additions)" ? "  " + text : text, attributes: [.font: AppFont.nsSans(size: AppFont.small), .foregroundColor: color]))
    }
    let right = card.maxX - (openFile ? Self.openFileWidth : 10)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingMiddle
    title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
    title.draw(
      with: NSRect(x: x, y: midY - DiffMetrics.lineHeight / 2, width: max(0, right - x), height: DiffMetrics.lineHeight),
      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])

    if openFile, !isDeleted {
      let label = NSAttributedString(
        string: "Open File", attributes: [.font: AppFont.nsSans(size: AppFont.small), .foregroundColor: ZedPalette.text])
      let size = label.size()
      label.draw(at: NSPoint(x: card.maxX - 12 - size.width, y: midY - size.height / 2))
    }
  }

  private func drawFileHeader(_ file: FileChange, collapsed: Bool) {
    if Theme.shared.isZed { return drawZedFileHeader(file, collapsed: collapsed) }
    // Zed draws file headers on its panel colour.
    (Theme.shared.panelBackground ?? .windowBackgroundColor).setFill()
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
        .init(pointSize: AppFont.small - 2, weight: .semibold).applying(.init(paletteColors: [.secondaryLabelColor])))
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
    // Style Zed: just a gap between hunks; their actions show on hover.
    if Theme.shared.isZed { return }
    let zed = false
    if !zed {
      Theme.shared.accentColor.withAlphaComponent(Self.tint(0.08)).setFill()
      bounds.fill()
    }
    var width = bounds.width - 24
    let zones = Self.hunkActionZones(rowWidth: bounds.width, action: hunkAction, restore: restoreAction)
    for zone in zones {
      // Restore is the quieter of the two: it's the one you can't take back.
      let color = zone.kind == .primary ? Theme.shared.accentColor : NSColor.secondaryLabelColor
      let label = NSAttributedString(
        string: zone.label, attributes: [.font: Self.hunkActionFont, .foregroundColor: color])
      label.draw(at: NSPoint(x: zone.labelX, y: (bounds.height - label.size().height) / 2))
    }
    if let leftmost = zones.last { width = leftmost.hit.lowerBound - 12 - 8 }
    if zed { return }
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
      attributes: [.font: AppFont.nsSans(size: AppFont.body), .foregroundColor: NSColor.secondaryLabelColor])
    note.draw(at: NSPoint(x: 16, y: (bounds.height - note.size().height) / 2))
  }

  // MARK: - Lines

  private func drawUnified(_ line: DiffLine) {
    Self.background(line.kind).setFill()
    bounds.fill()
    let left = metrics.blameWidth
    drawBlameColumn()
    let gutter = metrics.gutterWidth
    // Style Zed: one number column, the new side's; removed lines have none.
    let gutters: CGFloat = Theme.shared.isZed ? 1 : 2
    Self.gutterBackground(line.kind).setFill()
    NSRect(x: left, y: 0, width: gutters * gutter, height: bounds.height).fill()
    if Theme.shared.isZed {
      drawNumber(line.newNumber, rightEdge: left + gutter - 6, kind: line.kind)
    } else {
      drawNumber(line.oldNumber, rightEdge: left + gutter - 6)
      drawNumber(line.newNumber, rightEdge: left + 2 * gutter - 6)
    }
    drawCode(
      line, x: left + gutters * gutter, width: metrics.textWidth(rowWidth: bounds.width, split: false),
      inline: line.kind == .deletion ? nil : inlineBlame)
  }

  private func drawSplit(_ pair: SplitRow) {
    let pixel = 1 / (window?.backingScaleFactor ?? 2)
    let left = metrics.blameWidth
    drawBlameColumn()
    let half = (bounds.width - left - pixel) / 2
    drawSide(pair.left, number: pair.left?.oldNumber, x: left, width: half, inline: nil)
    Hairline.nsColor.setFill()
    NSRect(x: left + half, y: 0, width: pixel, height: bounds.height).fill()
    drawSide(pair.right, number: pair.right?.newNumber, x: left + half + pixel, width: half, inline: inlineBlame)
  }

  private func drawSide(_ line: DiffLine?, number: Int?, x: CGFloat, width: CGFloat, inline: BlameCommit?) {
    let gutter = metrics.gutterWidth
    (line.map { Self.background($0.kind) } ?? Self.emptySide).setFill()
    NSRect(x: x, y: 0, width: width, height: bounds.height).fill()
    Self.gutterBackground(line?.kind).setFill()
    NSRect(x: x, y: 0, width: gutter, height: bounds.height).fill()
    drawNumber(number, rightEdge: x + gutter - 6, kind: line?.kind)
    if let line {
      drawCode(line, x: x + gutter, width: metrics.textWidth(rowWidth: bounds.width, split: true), inline: inline)
    }
  }

  // MARK: - Blame

  /// "a1b2c3d Jordan   3 days ago" at the left of a line row, dimmed and a
  /// size down. Empty until the file's blame loads; drawing never waits.
  private func drawBlameColumn() {
    let width = metrics.blameWidth
    guard width > 0 else { return }
    Self.gutterBackground(.context).setFill()
    NSRect(x: 0, y: 0, width: width, height: bounds.height).fill()
    guard let blame, let context = NSGraphicsContext.current?.cgContext else { return }
    let font = DiffMetrics.smallFont
    let advance = DiffMetrics.smallAdvance
    let x = DiffMetrics.blamePadding
    let y = DiffMetrics.verticalPadding
    func draw(_ text: String, at x: CGFloat) {
      CodeText.drawSingleLine(text, color: .secondaryLabelColor, at: NSPoint(x: x, y: y), font: font, in: context)
    }
    guard blame.isCommitted else { return draw("Not committed yet", at: x) }
    draw(blame.shortID, at: x)
    draw(
      blame.shortAuthor(limit: DiffMetrics.blameNameColumns),
      at: x + CGFloat(DiffMetrics.blameIDColumns + 1) * advance)
    let date = BlameDate.text(for: blame.date)
    draw(date, at: width - DiffMetrics.blamePadding - CGFloat(date.count) * advance)
  }

  /// The blame column's tooltip: the full summary, author, and date.
  func view(
    _ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?
  ) -> String {
    blame?.tooltip ?? ""
  }

  /// Zed's inline blame: "Jordan, 3 days ago · Fix the thing" after the
  /// selected line's text, on its last wrapped line, cut to what fits.
  private func drawInlineBlame(_ blame: BlameCommit, after line: DiffLine, x: CGFloat, width: CGFloat, in context: CGContext) {
    // Non-ASCII text has no column count to place it by.
    guard line.columns >= 0 else { return }
    let perLine = max(1, Int(width / DiffMetrics.advance))
    let lastLine = line.columns == 0 ? 0 : (line.columns - 1) / perLine
    let used = line.columns - lastLine * perLine
    let gap = 3
    let room = perLine - used - gap
    guard room >= 8 else { return }
    var text = blame.inlineText()
    if text.count > room { text = String(text.prefix(room - 1)) + "\u{2026}" }
    CodeText.drawSingleLine(
      text, color: .tertiaryLabelColor,
      at: NSPoint(
        x: x + CGFloat(used + gap) * DiffMetrics.advance,
        y: DiffMetrics.verticalPadding + CGFloat(lastLine) * DiffMetrics.lineHeight),
      in: context)
  }

  private func drawNumber(_ number: Int?, rightEdge: CGFloat, kind: DiffLine.Kind? = nil) {
    guard let number, let context = NSGraphicsContext.current?.cgContext else { return }
    let text = String(number)
    // Style Zed colours a changed line's number like the change.
    let color: NSColor =
      Theme.shared.isZed && kind == .addition
      ? Theme.shared.createdLabel
      : Theme.shared.isZed && kind == .deletion ? Theme.shared.deletedLabel : Theme.shared.lineNumber
    CodeText.drawSingleLine(
      text, color: color,
      at: NSPoint(x: rightEdge - CGFloat(text.count) * DiffMetrics.advance, y: DiffMetrics.verticalPadding),
      in: context)
  }

  private func drawCode(_ line: DiffLine, x: CGFloat, width: CGFloat, inline: BlameCommit? = nil) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let marker: String
    switch line.kind {
    case .addition: marker = "+"
    case .deletion: marker = "-"
    case .context, .noNewline: marker = ""
    }
    if Theme.shared.isZed {
      // Zed marks a changed line with a bar at the edge, not + or -.
      if line.kind == .addition || line.kind == .deletion {
        let color =
          row?.inMixedHunk == true
          ? ZedPalette.versionModified : line.kind == .addition ? ZedPalette.versionAdded : ZedPalette.versionDeleted
        if row?.fileIsStaged == true {
          // Zed draws staged hunks' bars hollow.
          color.setStroke()
          let bar = NSBezierPath(rect: NSRect(x: x + 0.75, y: 0.5, width: 2.25, height: bounds.height - 1))
          bar.lineWidth = 1.5
          bar.stroke()
        } else {
          color.setFill()
          NSRect(x: x, y: 0, width: 3, height: bounds.height).fill()
        }
      }
    } else if !marker.isEmpty {
      CodeText.drawSingleLine(
        marker, color: .secondaryLabelColor,
        at: NSPoint(x: x + (DiffMetrics.markerWidth - DiffMetrics.advance) / 2, y: DiffMetrics.verticalPadding),
        in: context)
    }
    // Changed words, worked out when the diff was built; here they only
    // move past expanded tabs.
    let emphasis =
      line.emphasis.isEmpty
      ? [] : WordDiff.displayRanges(line.emphasis, in: line.text, tabWidth: DiffMetrics.tabWidth)
    CodeText.draw(
      DiffMetrics.displayText(line.text),
      color: line.kind == .noNewline ? .secondaryLabelColor : Theme.shared.codeText,
      at: NSPoint(x: x + DiffMetrics.markerWidth, y: DiffMetrics.verticalPadding),
      width: DiffMetrics.textDrawWidth(width), in: context,
      highlights: emphasis, highlightColor: Self.emphasis(line.kind))
    if let inline, line.kind == .context || line.kind == .addition {
      drawInlineBlame(inline, after: line, x: x + DiffMetrics.markerWidth, width: width, in: context)
    }
  }

  // MARK: - Colors

  private static var emptySide: NSColor { NSColor.secondaryLabelColor.withAlphaComponent(tint(0.06)) }

  private static func background(_ kind: DiffLine.Kind) -> NSColor {
    switch kind {
    case .addition: Theme.shared.added.withAlphaComponent(0.14)
    case .deletion: Theme.shared.removed.withAlphaComponent(0.14)
    case .context, .noNewline: Theme.shared.editorBackground
    }
  }

  /// Behind changed words: the line's own colour, stronger.
  private static func emphasis(_ kind: DiffLine.Kind) -> NSColor? {
    switch kind {
    case .addition: Theme.shared.added.withAlphaComponent(0.35)
    case .deletion: Theme.shared.removed.withAlphaComponent(0.35)
    case .context, .noNewline: nil
    }
  }

  private static func gutterBackground(_ kind: DiffLine.Kind?) -> NSColor {
    // Style Zed: the gutter takes the line's own colour, one band per line.
    if Theme.shared.isZed { return kind.map(background) ?? Theme.shared.editorBackground }
    return switch kind {
    case .addition: Theme.shared.added.withAlphaComponent(0.22)
    case .deletion: Theme.shared.removed.withAlphaComponent(0.22)
    case .context, .noNewline: NSColor.secondaryLabelColor.withAlphaComponent(tint(0.05))
    case nil: NSColor.secondaryLabelColor.withAlphaComponent(tint(0.08))
    }
  }
}
