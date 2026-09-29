import Foundation

/// What a piece of code is, for its colour. Named after the keys of Zed's
/// syntax themes, which `SyntaxTheme` maps them to.
enum SyntaxKind: UInt8, Sendable {
  case keyword, string, comment, docComment, number, boolean, type, function, constant, property
  case attribute, tag, preproc, variable, title
}

/// One coloured stretch of text, in UTF-16 offsets, the unit AppKit and
/// Core Text count in.
struct SyntaxSpan: Equatable, Sendable {
  let range: Range<Int>
  let kind: SyntaxKind
}

/// Where a line starts: inside a comment or string left open by an earlier
/// line, or not.
enum SyntaxState: Equatable, Sendable {
  case normal
  case blockComment(doc: Bool)
  case string(close: String)
  case tag
}

/// A language's lexical rules. Not a parser: comments, strings, numbers,
/// keywords and a few naming conventions, which is most of what colour
/// is for, at a cost that suits drawing a line at a time.
final class SyntaxLanguage: Sendable {
  enum Family: Sendable { case code, markup, markdown }

  let name: String
  let family: Family
  let lineComments: [[UInt16]]
  let blockComment: (open: [UInt16], close: [UInt16])?
  /// Characters that open and close a one-line string.
  let quotes: Set<UInt16>
  /// Delimiters of strings that can run over lines: `"""`, `'''`, backticks.
  let multilineQuotes: [[UInt16]]
  let keywords: Set<String>
  let types: Set<String>
  let booleans: Set<String>
  let constants: Set<String>
  /// `self`, `this`: Zed's variable.special.
  let specials: Set<String>
  let caseInsensitive: Bool
  /// `Name` is a type; `NAME` a constant.
  let namingConventions: Bool
  /// `@name`, and what it is: an attribute, or Ruby's instance variable.
  let atPrefix: SyntaxKind?
  /// `$name` is a variable: shell, PHP, Makefiles.
  let dollarVariables: Bool
  /// `#include` at the start of a line.
  let hashPreprocessor: Bool
  /// Rust's `#[derive(...)]`.
  let hashAttributes: Bool
  /// `key:` at the start of a line or after `{` is a property: JS, YAML.
  let colonKeys: Bool
  /// `"key":` is a property: JSON.
  let stringKeys: Bool
  /// `key =` at the start of a line is a property, `[section]` a type: TOML, INI.
  let equalsKeys: Bool
  /// `-` joins words: CSS, YAML, Lisp-ish names.
  let dashInNames: Bool
  /// `name: value` inside braces is a property: CSS.
  let cssProperties: Bool

  init(
    _ name: String, family: Family = .code, lineComments: [String] = [], blockComment: (String, String)? = nil,
    quotes: String = "\"'", multilineQuotes: [String] = [], keywords: String = "", types: String = "",
    booleans: String = "true false", constants: String = "", specials: String = "", caseInsensitive: Bool = false,
    namingConventions: Bool = true, atPrefix: SyntaxKind? = nil, dollarVariables: Bool = false,
    hashPreprocessor: Bool = false, hashAttributes: Bool = false, colonKeys: Bool = false, stringKeys: Bool = false,
    equalsKeys: Bool = false, dashInNames: Bool = false, cssProperties: Bool = false
  ) {
    func words(_ list: String) -> Set<String> {
      Set(list.split(separator: " ").map { caseInsensitive ? $0.lowercased() : String($0) })
    }
    self.name = name
    self.family = family
    self.lineComments = lineComments.map { Array($0.utf16) }
    self.blockComment = blockComment.map { (Array($0.0.utf16), Array($0.1.utf16)) }
    self.quotes = Set(quotes.utf16)
    self.multilineQuotes = multilineQuotes.map { Array($0.utf16) }
    self.keywords = words(keywords)
    self.types = words(types)
    self.booleans = words(booleans)
    self.constants = words(constants)
    self.specials = words(specials)
    self.caseInsensitive = caseInsensitive
    self.namingConventions = namingConventions
    self.atPrefix = atPrefix
    self.dollarVariables = dollarVariables
    self.hashPreprocessor = hashPreprocessor
    self.hashAttributes = hashAttributes
    self.colonKeys = colonKeys
    self.stringKeys = stringKeys
    self.equalsKeys = equalsKeys
    self.dashInNames = dashInNames
    self.cssProperties = cssProperties
  }
}

enum Syntax {
  /// Colours for `text`, which may hold several lines. `state` says where
  /// the first line starts and, afterwards, where the next one would.
  static func spans(in text: String, language: SyntaxLanguage, state: inout SyntaxState) -> [SyntaxSpan] {
    var lexer = Lexer(text: Array(text.utf16), language: language, state: state)
    switch language.family {
    case .code: lexer.code()
    case .markup: lexer.markup()
    case .markdown: lexer.markdown()
    }
    state = lexer.state
    return lexer.spans
  }

  /// One line of a diff, lexed on its own. A line inside a `/* ... */`
  /// block usually starts with `*`; that's taken as a comment.
  static func spans(inLine text: String, language: SyntaxLanguage) -> [SyntaxSpan] {
    var state = SyntaxState.normal
    if let block = language.blockComment, block.open.first == 0x2F /* / */ {
      let trimmed = text.drop { $0 == " " || $0 == "\t" }
      if trimmed.hasPrefix("*") && !trimmed.hasPrefix("*/") || trimmed.hasPrefix("*/") {
        let isDoc = trimmed.hasPrefix("* ") || trimmed == "*"
        state = .blockComment(doc: isDoc)
      }
    }
    return spans(in: text, language: language, state: &state)
  }
}

// MARK: - Lexer

private struct Lexer {
  let u: [UInt16]
  let language: SyntaxLanguage
  var state: SyntaxState
  var spans: [SyntaxSpan] = []
  var i = 0

  init(text: [UInt16], language: SyntaxLanguage, state: SyntaxState) {
    u = text
    self.language = language
    self.state = state
  }

  // Code units.
  static let newline: UInt16 = 10
  static let space: UInt16 = 32
  static let tab: UInt16 = 9
  static let backslash: UInt16 = 92

  mutating func add(_ start: Int, _ end: Int, _ kind: SyntaxKind) {
    guard end > start else { return }
    spans.append(SyntaxSpan(range: start..<end, kind: kind))
  }

  func at(_ index: Int) -> UInt16? { index < u.count && index >= 0 ? u[index] : nil }

  func matches(_ pattern: [UInt16], at index: Int) -> Bool {
    guard !pattern.isEmpty, index + pattern.count <= u.count else { return false }
    for k in 0..<pattern.count where u[index + k] != pattern[k] { return false }
    return true
  }

  func find(_ pattern: [UInt16], from index: Int) -> Int? {
    var k = index
    while k + pattern.count <= u.count {
      if matches(pattern, at: k) { return k }
      k += 1
    }
    return nil
  }

  func endOfLine(from index: Int) -> Int {
    var k = index
    while k < u.count, u[k] != Self.newline { k += 1 }
    return k
  }

  static func isLetter(_ c: UInt16) -> Bool {
    (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c >= 0x80
  }
  static func isDigit(_ c: UInt16) -> Bool { c >= 48 && c <= 57 }
  static func isSpace(_ c: UInt16) -> Bool { c == space || c == tab || c == 13 }

  func isNameCharacter(_ c: UInt16) -> Bool {
    Self.isLetter(c) || Self.isDigit(c) || (language.dashInNames && c == 45)
  }

  /// The first character after spaces from `index`, on this line.
  func nextNonSpace(from index: Int) -> (Int, UInt16)? {
    var k = index
    while k < u.count, Self.isSpace(u[k]) { k += 1 }
    guard k < u.count, u[k] != Self.newline else { return nil }
    return (k, u[k])
  }

  func previousNonSpace(before index: Int) -> UInt16? {
    var k = index - 1
    while k >= 0, Self.isSpace(u[k]) { k -= 1 }
    guard k >= 0, u[k] != Self.newline else { return nil }
    return u[k]
  }

  func atLineStart(_ index: Int) -> Bool {
    var k = index - 1
    while k >= 0, Self.isSpace(u[k]) { k -= 1 }
    return k < 0 || u[k] == Self.newline
  }

  // MARK: Pieces shared by every family

  /// Continues a comment or string left open, from `i`.
  mutating func resume() {
    switch state {
    case .normal, .tag: return
    case .blockComment(let doc):
      guard let close = language.blockComment?.close else {
        state = .normal
        return
      }
      let start = i
      if let end = find(close, from: i) {
        i = end + close.count
        state = .normal
      } else {
        i = u.count
      }
      add(start, i, doc ? .docComment : .comment)
    case .string(let close):
      let pattern = Array(close.utf16)
      let start = i
      if let end = findClosing(pattern, from: i) {
        i = end + pattern.count
        state = .normal
      } else {
        i = u.count
      }
      add(start, i, language.family == .markdown ? .string : .string)
    }
  }

  /// The closing delimiter from `index`, skipping backslash escapes.
  func findClosing(_ pattern: [UInt16], from index: Int) -> Int? {
    var k = index
    while k + pattern.count <= u.count {
      if u[k] == Self.backslash, pattern != [96, 96, 96] {
        k += 2
        continue
      }
      if matches(pattern, at: k) { return k }
      k += 1
    }
    return nil
  }

  /// A one-line string opened by `quote` at `i`.
  mutating func singleLineString() -> Int {
    let start = i
    let quote = u[i]
    i += 1
    while i < u.count, u[i] != Self.newline {
      if u[i] == Self.backslash {
        i += 2
        continue
      }
      if u[i] == quote {
        i += 1
        break
      }
      i += 1
    }
    i = min(i, u.count)
    return start
  }

  mutating func number() {
    let start = i
    let isHex = u[i] == 48 && (at(i + 1) == 120 || at(i + 1) == 88)
    i += 1
    while i < u.count {
      let c = u[i]
      if Self.isDigit(c) || Self.isLetter(c) {
        i += 1
      } else if c == 46, let next = at(i + 1), Self.isDigit(next) {
        i += 1
      } else if (c == 43 || c == 45), !isHex, let previous = at(i - 1), previous == 101 || previous == 69 {
        i += 1
      } else {
        break
      }
    }
    add(start, i, .number)
  }

  // MARK: Code

  mutating func code() {
    resume()
    while i < u.count {
      let c = u[i]
      if c == Self.newline || Self.isSpace(c) {
        i += 1
        continue
      }
      if let comment = language.lineComments.first(where: { matches($0, at: i) }),
        comment != [35] || i == 0 || Self.isSpace(u[i - 1]) || u[i - 1] == Self.newline
      {
        let end = endOfLine(from: i)
        let isDoc = comment == [47, 47] && at(i + 2) == 47 && at(i + 3) != 47
        add(i, end, isDoc ? .docComment : .comment)
        i = end
        continue
      }
      if let block = language.blockComment, matches(block.open, at: i) {
        let isDoc = block.open == [47, 42] && at(i + 2) == 42 && at(i + 3) != 47
        let start = i
        i += block.open.count
        if let end = find(block.close, from: i) {
          i = end + block.close.count
        } else {
          i = u.count
          state = .blockComment(doc: isDoc)
        }
        add(start, i, isDoc ? .docComment : .comment)
        continue
      }
      if let delimiter = language.multilineQuotes.first(where: { matches($0, at: i) }) {
        let start = i
        i += delimiter.count
        if let end = findClosing(delimiter, from: i) {
          i = end + delimiter.count
        } else {
          i = u.count
          state = .string(close: String(decoding: delimiter, as: UTF16.self))
        }
        add(start, i, .string)
        continue
      }
      if language.quotes.contains(c) {
        let start = singleLineString()
        let isKey = language.stringKeys && nextNonSpace(from: i)?.1 == 58
        add(start, i, isKey ? .property : .string)
        continue
      }
      if Self.isDigit(c) || (c == 46 && at(i + 1).map(Self.isDigit) == true && !(at(i - 1).map(isNameCharacter) ?? false)) {
        number()
        continue
      }
      if c == 35 /* # */ {
        if language.hashAttributes, at(i + 1) == 91 || (at(i + 1) == 33 && at(i + 2) == 91) {
          let start = i
          let end = endOfLine(from: i)
          var k = i
          var depth = 0
          while k < end {
            if u[k] == 91 { depth += 1 }
            if u[k] == 93 {
              depth -= 1
              if depth == 0 {
                k += 1
                break
              }
            }
            k += 1
          }
          i = k
          add(start, i, .attribute)
          continue
        }
        if language.hashPreprocessor, atLineStart(i) {
          let start = i
          i += 1
          while i < u.count, Self.isLetter(u[i]) { i += 1 }
          add(start, i, .preproc)
          continue
        }
        if language.cssProperties, let next = at(i + 1), isNameCharacter(next) {
          let start = i
          i += 1
          while i < u.count, isNameCharacter(u[i]) { i += 1 }
          add(start, i, previousNonSpace(before: start) == 58 ? .number : .type)
          continue
        }
      }
      if c == 64 /* @ */, let kind = language.atPrefix, let next = at(i + 1), Self.isLetter(next) {
        let start = i
        i += 1
        while i < u.count, isNameCharacter(u[i]) || u[i] == 46 { i += 1 }
        add(start, i, kind)
        continue
      }
      if c == 36 /* $ */, language.dollarVariables, let next = at(i + 1) {
        let start = i
        i += 1
        if next == 123 || next == 40 /* { ( */ {
          let close: UInt16 = next == 123 ? 125 : 41
          while i < u.count, u[i] != close, u[i] != Self.newline { i += 1 }
          if i < u.count, u[i] == close { i += 1 }
        } else {
          while i < u.count, Self.isLetter(u[i]) || Self.isDigit(u[i]) { i += 1 }
          if i == start + 1, i < u.count, "@#?*!$-0".utf16.contains(u[i]) { i += 1 }
        }
        add(start, i, .variable)
        continue
      }
      if language.equalsKeys, c == 91 /* [ */, atLineStart(i) {
        let start = i
        let end = endOfLine(from: i)
        while i < end, u[i] != 93 { i += 1 }
        if i < end { i += 1 }
        add(start, i, .type)
        continue
      }
      if Self.isLetter(c) {
        word()
        continue
      }
      i += 1
    }
  }

  mutating func word() {
    let start = i
    while i < u.count, isNameCharacter(u[i]) { i += 1 }
    // Ruby's `empty?` and `save!`.
    if language.atPrefix == .variable, i < u.count, u[i] == 63 || u[i] == 33, at(i + 1) != 61 { i += 1 }
    let raw = String(decoding: u[start..<i], as: UTF16.self)
    let word = language.caseInsensitive ? raw.lowercased() : raw
    let previous = previousNonSpace(before: start)
    let next = nextNonSpace(from: i)
    let afterDot = previous == 46 && at(start - 1) == 46
    let callsNext = next?.1 == 40 /* ( */ || (next?.1 == 33 && at(next!.0 + 1) == 40)

    if language.colonKeys, next?.1 == 58, at(next!.0 + 1) != 58, previous == nil || previous == 123 || previous == 45 {
      return add(start, i, .property)
    }
    if language.equalsKeys, next?.1 == 61, atLineStart(start) {
      return add(start, i, .property)
    }
    if language.cssProperties, next?.1 == 58, let after = at(next!.0 + 1), Self.isSpace(after) || after == Self.newline {
      return add(start, i, .property)
    }
    if afterDot {
      return add(start, i, callsNext ? .function : .property)
    }
    if language.keywords.contains(word) { return add(start, i, .keyword) }
    if language.booleans.contains(word) { return add(start, i, .boolean) }
    if language.constants.contains(word) { return add(start, i, .constant) }
    if language.specials.contains(word) { return add(start, i, .variable) }
    if language.types.contains(word) { return add(start, i, .type) }
    if callsNext { return add(start, i, .function) }
    if language.namingConventions, let first = raw.utf16.first, first >= 65 && first <= 90 {
      let hasLower = raw.utf16.contains { $0 >= 97 && $0 <= 122 }
      if !hasLower && raw.utf16.count > 1 { return add(start, i, .constant) }
      if hasLower { return add(start, i, .type) }
    }
  }

  // MARK: Markup

  mutating func markup() {
    resume()
    let commentOpen = Array("<!--".utf16)
    let commentClose = Array("-->".utf16)
    while i < u.count {
      let c = u[i]
      if state == .tag {
        if c == 62 /* > */ {
          state = .normal
          i += 1
        } else if c == 34 || c == 39 {
          let start = singleLineString()
          add(start, i, .string)
        } else if Self.isLetter(c) || c == 58 || c == 64 {
          let start = i
          while i < u.count, isNameCharacter(u[i]) || u[i] == 45 || u[i] == 58 || u[i] == 64 || u[i] == 46 { i += 1 }
          add(start, i, .attribute)
        } else {
          i += 1
        }
        continue
      }
      if matches(commentOpen, at: i) {
        let start = i
        if let end = find(commentClose, from: i + 4) {
          i = end + 3
        } else {
          i = u.count
          state = .blockComment(doc: false)
        }
        add(start, i, .comment)
        continue
      }
      if c == 60 /* < */, let next = at(i + 1), Self.isLetter(next) || next == 47 || next == 33 || next == 63 {
        i += 1
        if u[i] == 47 || u[i] == 33 || u[i] == 63 { i += 1 }
        let start = i
        while i < u.count, isNameCharacter(u[i]) || u[i] == 45 || u[i] == 58 || u[i] == 46 { i += 1 }
        add(start, i, .tag)
        state = .tag
        continue
      }
      if c == 38 /* & */ {
        let start = i
        var k = i + 1
        while k < u.count, k - i < 10, Self.isLetter(u[k]) || Self.isDigit(u[k]) || u[k] == 35 { k += 1 }
        if k < u.count, u[k] == 59, k > i + 1 {
          i = k + 1
          add(start, i, .constant)
          continue
        }
      }
      i += 1
    }
  }

  // MARK: Markdown

  mutating func markdown() {
    resume()
    let fence = Array("```".utf16)
    while i < u.count {
      let lineStart = i
      let end = endOfLine(from: i)
      var k = i
      while k < end, Self.isSpace(u[k]) { k += 1 }
      if matches(fence, at: k) {
        let close = end
        i = close
        if let finish = find(fence, from: close) {
          i = endOfLine(from: finish)
        } else {
          i = u.count
          state = .string(close: "```")
        }
        add(lineStart, i, .string)
        if i < u.count { i += 1 }
        continue
      }
      if k < end, u[k] == 35 /* # */ {
        add(k, end, .title)
      } else {
        if k < end, u[k] == 45 || u[k] == 42 || u[k] == 43, k + 1 < end, Self.isSpace(u[k + 1]) {
          add(k, k + 1, .keyword)
        }
        if k < end, u[k] == 62 /* > */ { add(k, end, .comment) }
        var j = k
        while j < end {
          if u[j] == 96 /* ` */ {
            let start = j
            j += 1
            while j < end, u[j] != 96 { j += 1 }
            j = min(j + 1, end)
            add(start, j, .string)
            continue
          }
          if u[j] == 93 /* ] */, j + 1 < end, u[j + 1] == 40 /* ( */ {
            let start = j + 1
            j += 2
            while j < end, u[j] != 41 { j += 1 }
            j = min(j + 1, end)
            add(start, j, .constant)
            continue
          }
          j += 1
        }
      }
      i = end + 1
    }
  }
}
