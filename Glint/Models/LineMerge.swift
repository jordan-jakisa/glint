import Foundation

/// A three-way merge of lines: what you have (`ours`) and what's on disk now
/// (`theirs`), both descended from what was on disk before (`base`). Changes
/// on one side only are taken as they are; where both sides changed the
/// same lines differently, yours win and the result says so.
enum LineMerge {
  struct Result: Equatable {
    var lines: [String]
    var conflicted: Bool
    /// For each boundary before an `ours` line (and one past the end),
    /// where it lands in `lines`: rounded back to the start of a change
    /// that straddles it (`lower`), or on to its end (`upper`).
    var lower: [Int]
    var upper: [Int]
  }

  static func merge(base: [String], ours: [String], theirs: [String]) -> Result {
    let toOurs = matching(base, ours)
    let toTheirs = matching(base, theirs)
    var lines: [String] = []
    lines.reserveCapacity(max(ours.count, theirs.count))
    var lower = [Int](repeating: 0, count: ours.count + 1)
    var upper = [Int](repeating: 0, count: ours.count + 1)
    var conflicted = false
    var b = 0, o = 0, t = 0

    while b < base.count || o < ours.count || t < theirs.count {
      // The next base line both sides kept.
      var j = b
      while j < base.count, toOurs[j] == nil || toTheirs[j] == nil { j += 1 }
      let oursEnd = j < base.count ? toOurs[j]! : ours.count
      let theirsEnd = j < base.count ? toTheirs[j]! : theirs.count

      if j == b, oursEnd == o, theirsEnd == t {
        lower[o] = lines.count
        upper[o] = lines.count
        lines.append(ours[o])
        b += 1
        o += 1
        t += 1
        continue
      }

      let baseChunk = base[b..<j]
      let oursChunk = ours[o..<oursEnd]
      let theirsChunk = theirs[t..<theirsEnd]
      let start = lines.count
      if oursChunk.elementsEqual(baseChunk) {
        lines += theirsChunk
      } else if theirsChunk.elementsEqual(baseChunk) || oursChunk.elementsEqual(theirsChunk) {
        lines += oursChunk
      } else {
        lines += oursChunk
        conflicted = true
      }
      for k in o..<oursEnd {
        lower[k] = start
        upper[k] = lines.count
      }
      b = j
      o = oursEnd
      t = theirsEnd
    }
    lower[ours.count] = lines.count
    upper[ours.count] = lines.count
    return Result(lines: lines, conflicted: conflicted, lower: lower, upper: upper)
  }

  /// For each line of `from`, the line of `to` it survives as, if any.
  static func matching(_ from: [String], _ to: [String]) -> [Int?] {
    let difference = to.difference(from: from)
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in difference {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    var result = [Int?](repeating: nil, count: from.count)
    var j = 0
    for i in 0..<from.count where !removed.contains(i) {
      while inserted.contains(j) { j += 1 }
      result[i] = j
      j += 1
    }
    return result
  }
}
