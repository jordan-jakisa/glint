import AppKit
import CoreText

/// Draws monospaced code with Core Text directly. `NSAttributedString.draw`
/// goes through TextKit and cost most of a frame for a screenful of rows; a
/// typesetter that breaks lines by character cluster is several times
/// cheaper, and breaking by cluster is also what makes row heights
/// arithmetic (see `DiffMetrics.wrappedLines`).
@MainActor
enum CodeText {
  /// Draws `text` wrapped to `width`, one line per `lineHeight`, starting at
  /// `origin` (top-left, in a flipped view).
  ///
  /// `highlights` (UTF-16 ranges of `text`, sorted) get `highlightColor`
  /// behind them, on every wrapped line they reach: the changed words of a
  /// word diff.
  static func draw(
    _ text: String, color: NSColor, at origin: NSPoint, width: CGFloat, in context: CGContext,
    highlights: [Range<Int>] = [], highlightColor: NSColor? = nil
  ) {
    guard !text.isEmpty else { return }
    let typesetter = CTTypesetterCreateWithAttributedString(attributed(text, color: color))
    let length = (text as NSString).length
    let highlightFill = highlights.isEmpty ? nil : highlightColor?.cgColor
    var start = 0
    var y = origin.y
    while start < length {
      let count = max(1, CTTypesetterSuggestClusterBreak(typesetter, start, Double(width)))
      let line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
      if let highlightFill {
        fill(highlights, of: line, in: start..<(start + count), fill: highlightFill, x: origin.x, top: y, context: context)
      }
      drawLine(line, x: origin.x, top: y, in: context)
      start += count
      y += DiffMetrics.lineHeight
    }
  }

  /// One unwrapped line: line numbers, markers, blame. `font` defaults to
  /// the diff's; a smaller one sits on the same baseline as the code.
  static func drawSingleLine(
    _ text: String, color: NSColor, at origin: NSPoint, font: NSFont = DiffMetrics.font, in context: CGContext
  ) {
    let line = CTLineCreateWithAttributedString(attributed(text, color: color, font: font))
    drawLine(line, x: origin.x, top: origin.y, in: context)
  }

  /// How many lines `text` wraps to at `width`, the same way `draw` wraps it.
  static func lineCount(_ text: String, width: CGFloat) -> Int {
    guard !text.isEmpty else { return 1 }
    let typesetter = CTTypesetterCreateWithAttributedString(attributed(text, color: .labelColor))
    let length = (text as NSString).length
    var start = 0
    var lines = 0
    while start < length {
      start += max(1, CTTypesetterSuggestClusterBreak(typesetter, start, Double(width)))
      lines += 1
    }
    return max(lines, 1)
  }

  private static func attributed(_ text: String, color: NSColor, font: NSFont = DiffMetrics.font) -> CFAttributedString {
    // Core Text wants a CGColor. Resolving here, inside drawing, picks the
    // view's light or dark appearance.
    let attributes: [CFString: Any] = [
      kCTFontAttributeName: font,
      kCTForegroundColorAttributeName: color.cgColor,
    ]
    return CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
  }

  /// The parts of `ranges` on this wrapped line, filled behind its text.
  private static func fill(
    _ ranges: [Range<Int>], of line: CTLine, in span: Range<Int>, fill: CGColor, x: CGFloat, top: CGFloat,
    context: CGContext
  ) {
    context.setFillColor(fill)
    for range in ranges {
      if range.lowerBound >= span.upperBound { break }
      let lower = max(range.lowerBound, span.lowerBound)
      let upper = min(range.upperBound, span.upperBound)
      guard lower < upper else { continue }
      let start = CTLineGetOffsetForStringIndex(line, lower, nil)
      let end = CTLineGetOffsetForStringIndex(line, upper, nil)
      context.fill(CGRect(x: x + start, y: top, width: max(0, end - start), height: DiffMetrics.lineHeight))
    }
  }

  private static func drawLine(_ line: CTLine, x: CGFloat, top: CGFloat, in context: CGContext) {
    context.saveGState()
    // The view is flipped; text must not be.
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: x, y: top + DiffMetrics.font.ascender)
    CTLineDraw(line, context)
    context.restoreGState()
  }
}
