import AppKit
import SwiftUI

/// A code editor: the diff's font, syntax colours, and line numbers from
/// `firstLine`. Text that changes from outside, the file on disk, is
/// patched in place, so your cursor and undo stay where they were.
struct CodeEditor: NSViewRepresentable {
  @Binding var text: String
  let language: SyntaxLanguage?
  let firstLine: Int

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSScrollView {
    let textView = NSTextView(usingTextLayoutManager: false)
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.smartInsertDeleteEnabled = false
    textView.font = DiffMetrics.font
    textView.textColor = Theme.shared.codeText
    textView.insertionPointColor = Theme.shared.accentColor
    textView.backgroundColor = Theme.shared.editorBackground
    textView.drawsBackground = true
    textView.textContainerInset = NSSize(width: 4, height: 8)
    // Code doesn't wrap, as in Zed: long lines scroll sideways.
    textView.isHorizontallyResizable = true
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
    let style = NSMutableParagraphStyle()
    style.minimumLineHeight = DiffMetrics.lineHeight
    style.maximumLineHeight = DiffMetrics.lineHeight
    style.tabStops = []
    style.defaultTabInterval = DiffMetrics.advance * CGFloat(DiffMetrics.tabWidth)
    textView.defaultParagraphStyle = style
    textView.typingAttributes = [.font: DiffMetrics.font, .paragraphStyle: style, .foregroundColor: Theme.shared.codeText]
    textView.string = text
    textView.textStorage?.setAttributes(textView.typingAttributes, range: NSRange(location: 0, length: (text as NSString).length))

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.drawsBackground = true
    scrollView.backgroundColor = Theme.shared.editorBackground
    let ruler = LineNumberRuler(textView: textView, scrollView: scrollView)
    ruler.firstLine = firstLine
    scrollView.verticalRulerView = ruler
    scrollView.hasVerticalRuler = true
    scrollView.rulersVisible = true
    // Lays the text out beside the gutter, not under it.
    scrollView.tile()
    context.coordinator.highlight(textView)
    DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? NSTextView else { return }
    if let ruler = scrollView.verticalRulerView as? LineNumberRuler, ruler.firstLine != firstLine {
      ruler.firstLine = firstLine
    }
    if textView.string != text { context.coordinator.replace(in: textView, with: text) }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: CodeEditor

    init(_ parent: CodeEditor) { self.parent = parent }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      if parent.text != textView.string { parent.text = textView.string }
      highlight(textView)
      textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    func textViewDidChangeSelection(_ notification: Notification) {
      (notification.object as? NSTextView)?.enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    /// Replaces only what differs, as an undoable edit, and keeps the
    /// cursor on the same text.
    func replace(in textView: NSTextView, with new: String) {
      guard !textView.hasMarkedText() else { return }
      let old = textView.string as NSString
      let replacement = new as NSString
      var prefix = 0
      let shorter = min(old.length, replacement.length)
      while prefix < shorter, old.character(at: prefix) == replacement.character(at: prefix) { prefix += 1 }
      var suffix = 0
      while suffix < shorter - prefix,
        old.character(at: old.length - 1 - suffix) == replacement.character(at: replacement.length - 1 - suffix)
      {
        suffix += 1
      }
      let range = NSRange(location: prefix, length: old.length - prefix - suffix)
      let inserted = replacement.substring(with: NSRange(location: prefix, length: replacement.length - prefix - suffix))
      let delta = (inserted as NSString).length - range.length
      let selection = textView.selectedRange()
      guard textView.shouldChangeText(in: range, replacementString: inserted) else { return }
      textView.textStorage?.replaceCharacters(in: range, with: NSAttributedString(string: inserted, attributes: textView.typingAttributes))
      textView.didChangeText()
      // Text after the change moves with it; text inside it keeps its offset.
      var location = selection.location
      if location >= NSMaxRange(range) {
        location += delta
      } else if location > range.location {
        location = min(location, range.location + (inserted as NSString).length)
      }
      let length = min(selection.length, max(0, (new as NSString).length - location))
      textView.setSelectedRange(NSRange(location: location, length: length))
    }

    /// Colours the whole text. Temporary attributes only change how it's
    /// drawn, so they cost no layout and never enter undo.
    func highlight(_ textView: NSTextView) {
      guard let layoutManager = textView.layoutManager else { return }
      let text = textView.string
      let full = NSRange(location: 0, length: (text as NSString).length)
      layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: full)
      guard let language = parent.language, SyntaxTheme.isEnabled else { return }
      var state = SyntaxState.normal
      for span in Syntax.spans(in: text, language: language, state: &state) {
        layoutManager.addTemporaryAttribute(
          .foregroundColor, value: SyntaxTheme.color(span.kind),
          forCharacterRange: NSRange(location: span.range.lowerBound, length: span.range.count))
      }
    }
  }
}

/// The line numbers beside the editor, Zed's way: dim, with the cursor's
/// line brighter.
final class LineNumberRuler: NSRulerView {
  var firstLine = 1 {
    didSet {
      updateThickness()
      needsDisplay = true
    }
  }
  private weak var textView: NSTextView?

  init(textView: NSTextView, scrollView: NSScrollView) {
    self.textView = textView
    super.init(scrollView: scrollView, orientation: .verticalRuler)
    clientView = textView
    updateThickness()
    scrollView.contentView.postsBoundsChangedNotifications = true
    NotificationCenter.default.addObserver(
      self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
  }

  required init(coder: NSCoder) { fatalError("not used") }

  @objc private func scrolled() { needsDisplay = true }

  private func updateThickness() {
    let lines = (textView?.string.utf16.reduce(0) { $1 == 10 ? $0 + 1 : $0 } ?? 0) + 1
    let digits = max(String(firstLine + lines).count, 3)
    let thickness = ceil(CGFloat(digits) * DiffMetrics.advance + 24)
    guard ruleThickness != thickness else { return }
    ruleThickness = thickness
    scrollView?.tile()
  }

  override var isOpaque: Bool { true }

  override func draw(_ dirtyRect: NSRect) {
    Theme.shared.editorBackground.setFill()
    bounds.fill()
    drawHashMarksAndLabels(in: dirtyRect)
  }

  override func drawHashMarksAndLabels(in rect: NSRect) {
    guard let textView, let layoutManager = textView.layoutManager, let container = textView.textContainer,
      let context = NSGraphicsContext.current?.cgContext
    else { return }
    updateThickness()
    let text = textView.string as NSString
    let visible = textView.visibleRect
    let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: container)
    let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
    let cursor = textView.selectedRange().location

    // The number of the first visible line: the lines before it.
    var line = firstLine
    var index = 0
    while index < characters.location {
      let range = text.lineRange(for: NSRange(location: index, length: 0))
      if NSMaxRange(range) > characters.location { break }
      index = NSMaxRange(range)
      line += 1
    }
    let origin = textView.textContainerOrigin
    func draw(_ number: Int, fragmentTop: CGFloat, current: Bool) {
      let y = convert(NSPoint(x: 0, y: fragmentTop + origin.y), from: textView).y
      let label = String(number)
      CodeText.drawSingleLine(
        label, color: current ? Theme.shared.codeText : Theme.shared.lineNumber,
        at: NSPoint(x: ruleThickness - 12 - CGFloat(label.count) * DiffMetrics.advance, y: y), in: context)
    }
    while index < text.length, index <= NSMaxRange(characters) {
      let range = text.lineRange(for: NSRange(location: index, length: 0))
      let glyph = layoutManager.glyphIndexForCharacter(at: index)
      let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
      let current = cursor >= range.location && (cursor < NSMaxRange(range) || NSMaxRange(range) == text.length)
      draw(line, fragmentTop: fragment.minY, current: current)
      index = NSMaxRange(range)
      line += 1
    }
    // The empty line after a final newline.
    let extra = layoutManager.extraLineFragmentRect
    if extra.height > 0 || text.length == 0 {
      draw(line, fragmentTop: extra.minY, current: cursor == text.length)
    }
  }
}
