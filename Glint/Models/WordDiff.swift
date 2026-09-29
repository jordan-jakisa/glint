import Foundation

/// Which words changed within a changed line, like Zed's word diff. A run of
/// deleted lines pairs up with the run of added lines after it (the way
/// `SplitRow.pair` lines them up), and each pair is diffed token by token.
/// The changed tokens become `DiffLine.emphasis`, drawn as a stronger tint.
///
/// Runs where the diff is built, off the main thread, never while drawing.
/// Every pair is bounded (line length, edit distance), so the cost stays
/// linear in the size of the diff.
enum WordDiff {
  /// On unless you turned it off in Settings.
  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: "wordDiff") as? Bool ?? true
  }

  /// Longer lines (minified code, data) are left alone.
  static let maxLineLength = 500
  /// Pairs sharing less than this much of their text are rewrites, not
  /// edits; highlighting them would just be confetti.
  static let minSimilarity = 0.4
  /// Hunks with more changed lines than this are skipped outright.
  static let maxChangedLines = 20_000
  /// Most token edits looked for in one pair before giving up.
  static let maxEdits = 64

  /// The hunk's lines with `emphasis` filled in for every paired change.
  static func emphasize(_ lines: [DiffLine]) -> [DiffLine] {
    var changed = 0
    for line in lines where line.kind == .addition || line.kind == .deletion { changed += 1 }
    guard changed > 1, changed <= maxChangedLines else { return lines }

    var result = lines
    var index = 0
    while index < result.count {
      guard result[index].kind == .deletion else {
        index += 1
        continue
      }
      var deletions: [Int] = []
      while index < result.count, result[index].kind == .deletion || result[index].kind == .noNewline {
        if result[index].kind == .deletion { deletions.append(index) }
        index += 1
      }
      var additions: [Int] = []
      while index < result.count, result[index].kind == .addition || result[index].kind == .noNewline {
        if result[index].kind == .addition { additions.append(index) }
        index += 1
      }
      for (old, new) in zip(deletions, additions) {
        guard let ranges = ranges(old: result[old].text, new: result[new].text) else { continue }
        result[old].emphasis = ranges.old
        result[new].emphasis = ranges.new
      }
    }
    return result
  }

  /// The changed ranges of each line, in UTF-16 offsets, or nil when the
  /// pair shouldn't be highlighted (too long, or too different).
  static func ranges(old: String, new: String) -> (old: [Range<Int>], new: [Range<Int>])? {
    let a = Array(old.utf16)
    let b = Array(new.utf16)
    guard a.count <= maxLineLength, b.count <= maxLineLength, a != b else { return nil }
    let oldTokens = tokens(a)
    let newTokens = tokens(b)

    // Common tokens at both ends are the usual case and cost nothing to skip.
    var prefix = 0
    while prefix < oldTokens.count, prefix < newTokens.count,
      a[oldTokens[prefix]] == b[newTokens[prefix]]
    {
      prefix += 1
    }
    var suffix = 0
    while suffix < oldTokens.count - prefix, suffix < newTokens.count - prefix,
      a[oldTokens[oldTokens.count - 1 - suffix]] == b[newTokens[newTokens.count - 1 - suffix]]
    {
      suffix += 1
    }
    let oldMiddle = Array(oldTokens[prefix..<(oldTokens.count - suffix)])
    let newMiddle = Array(newTokens[prefix..<(newTokens.count - suffix)])
    guard
      let (removed, inserted) = edits(
        oldMiddle.count, newMiddle.count, equal: { a[oldMiddle[$0]] == b[newMiddle[$1]] })
    else { return nil }

    // How much visible text the two lines share. Whitespace doesn't count,
    // or any two indented lines would look alike.
    var visible = 0
    var common = 0
    func count(_ tokens: [Range<Int>], _ units: [UInt16], _ changed: Set<Int>) {
      for (i, token) in tokens.enumerated() where !isSpace(units[token.lowerBound]) {
        visible += token.count
        // Tokens outside the middle are the shared prefix and suffix.
        if !changed.contains(i - prefix) { common += token.count }
      }
    }
    count(oldTokens, a, removed)
    count(newTokens, b, inserted)
    guard visible > 0, Double(common) / Double(visible) >= minSimilarity else { return nil }

    return (
      merge(removed.sorted().map { oldMiddle[$0] }, units: a),
      merge(inserted.sorted().map { newMiddle[$0] }, units: b)
    )
  }

  // MARK: - Tokens

  /// Words (letters, digits, `_`, and anything non-ASCII), runs of
  /// whitespace, and single punctuation characters. Non-ASCII units never
  /// split, so every boundary sits between whole characters.
  static func tokens(_ units: [UInt16]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    result.reserveCapacity(units.count / 3 + 1)
    var start = 0
    while start < units.count {
      let unit = units[start]
      var end = start + 1
      if isWord(unit) {
        while end < units.count, isWord(units[end]) { end += 1 }
      } else if isSpace(unit) {
        while end < units.count, isSpace(units[end]) { end += 1 }
      }
      result.append(start..<end)
      start = end
    }
    return result
  }

  private static func isWord(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x30...0x39, 0x41...0x5A, 0x61...0x7A, 0x5F: true
    case 0x80...: true
    default: false
    }
  }

  private static func isSpace(_ unit: UInt16) -> Bool {
    unit == 0x20 || unit == 0x09
  }

  /// Adjacent changed tokens as single ranges. Whitespace between two
  /// changes joins them, so `foo bar` to `baz qux` is one highlight.
  private static func merge(_ ranges: [Range<Int>], units: [UInt16]) -> [Range<Int>] {
    var result: [Range<Int>] = []
    for range in ranges {
      if let last = result.last,
        last.upperBound == range.lowerBound
          || (last.upperBound..<range.lowerBound).allSatisfy({ isSpace(units[$0]) })
      {
        result[result.count - 1] = last.lowerBound..<range.upperBound
      } else {
        result.append(range)
      }
    }
    return result
  }

  // MARK: - Myers

  /// Indices of the old tokens removed and new tokens inserted by a shortest
  /// edit script (Myers' O(ND) diff), or nil past `maxEdits`.
  private static func edits(_ n: Int, _ m: Int, equal: (Int, Int) -> Bool) -> (Set<Int>, Set<Int>)? {
    if n == 0 { return ([], Set(0..<m)) }
    if m == 0 { return (Set(0..<n), []) }
    let limit = min(n + m, maxEdits)
    let offset = limit + 1
    var v = [Int](repeating: 0, count: 2 * limit + 3)
    var trace: [[Int]] = []
    var found = false
    search: for d in 0...limit {
      trace.append(v)
      for k in stride(from: -d, through: d, by: 2) {
        var x =
          (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1]))
          ? v[offset + k + 1] : v[offset + k - 1] + 1
        var y = x - k
        while x < n, y < m, equal(x, y) {
          x += 1
          y += 1
        }
        v[offset + k] = x
        if x >= n, y >= m {
          found = true
          break search
        }
      }
    }
    guard found else { return nil }

    var removed = Set<Int>()
    var inserted = Set<Int>()
    var x = n
    var y = m
    for d in stride(from: trace.count - 1, through: 1, by: -1) {
      let v = trace[d]
      let k = x - y
      let previousK =
        (k == -d || (k != d && v[offset + k - 1] < v[offset + k + 1])) ? k + 1 : k - 1
      let previousX = v[offset + previousK]
      let previousY = previousX - previousK
      while x > previousX, y > previousY {
        x -= 1
        y -= 1
      }
      if x == previousX { inserted.insert(previousY) } else { removed.insert(previousX) }
      x = previousX
      y = previousY
    }
    return (removed, inserted)
  }

  // MARK: - Drawing support

  /// `ranges` moved from the line's own text to its display text, where tabs
  /// are spaces (see `DiffMetrics.displayText`, which this mirrors).
  static func displayRanges(_ ranges: [Range<Int>], in text: String, tabWidth: Int) -> [Range<Int>] {
    guard !ranges.isEmpty, text.utf8.contains(UInt8(ascii: "\t")) else { return ranges }
    var map: [Int] = []
    map.reserveCapacity(text.utf16.count + 1)
    var display = 0
    var column = 0
    for character in text {
      let width = character.utf16.count
      map.append(display)
      for _ in 1..<max(width, 1) { map.append(display) }
      if character == "\t" {
        let spaces = tabWidth - column % tabWidth
        display += spaces
        column += spaces
      } else {
        display += width
        column += 1
      }
    }
    map.append(display)
    return ranges.compactMap { range in
      guard range.lowerBound < map.count, range.upperBound < map.count else { return nil }
      return map[range.lowerBound]..<map[range.upperBound]
    }
  }
}
