import Foundation

/// JSON that round-trips the way Jupyter writes it: numbers keep their
/// exact text (`1.0` stays `1.0`), and `write` matches Python's
/// `json.dumps(sort_keys=True, indent=1, ensure_ascii=False)`, which is what
/// nbformat uses. `JSONSerialization` would turn `1.0` into `1` and reorder
/// keys, rewriting every notebook it saved.
enum JSONValue: Equatable, Sendable {
  case null
  case bool(Bool)
  /// The literal as written, so it's written back the same.
  case number(String)
  case string(String)
  case array([JSONValue])
  case object(JSONObject)

  static func number(_ value: Double) -> JSONValue {
    value.rounded() == value && abs(value) < 1e15 ? .number(String(Int(value))) : .number(String(value))
  }

  var string: String? { if case .string(let text) = self { return text } else { return nil } }
  var array: [JSONValue]? { if case .array(let items) = self { return items } else { return nil } }
  var int: Int? { if case .number(let text) = self { return Int(text) ?? Double(text).map { Int($0) } } else { return nil } }

  subscript(key: String) -> JSONValue? {
    get { if case .object(let object) = self { return object[key] } else { return nil } }
    set {
      guard case .object(var object) = self else { return }
      object[key] = newValue
      self = .object(object)
    }
  }

  // MARK: Reading

  static func parse(_ data: Data) throws -> JSONValue { try parseDetailed(data).value }

  /// `escapesNonASCII`: the file wrote non-ASCII text as `\uXXXX` (Python's
  /// `ensure_ascii`), so writing it back should too.
  static func parseDetailed(_ data: Data) throws -> (value: JSONValue, escapesNonASCII: Bool) {
    var parser = Parser(bytes: Array(data))
    parser.skipSpace()
    let value = try parser.value()
    parser.skipSpace()
    guard parser.index == parser.bytes.count else { throw ParseError.trailing }
    return (value, parser.sawEscapedNonASCII)
  }

  enum ParseError: Error { case unexpected(Int), trailing, badString(Int) }

  private struct Parser {
    let bytes: [UInt8]
    var index = 0
    var sawEscapedNonASCII = false

    mutating func skipSpace() {
      while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    mutating func value() throws -> JSONValue {
      guard index < bytes.count else { throw ParseError.unexpected(index) }
      switch bytes[index] {
      case UInt8(ascii: "{"):
        index += 1
        var object = JSONObject()
        skipSpace()
        if bytes[index] == UInt8(ascii: "}") {
          index += 1
          return .object(object)
        }
        while true {
          skipSpace()
          guard case .string(let key) = try value() else { throw ParseError.unexpected(index) }
          skipSpace()
          guard bytes[index] == UInt8(ascii: ":") else { throw ParseError.unexpected(index) }
          index += 1
          skipSpace()
          object[key] = try value()
          skipSpace()
          if bytes[index] == UInt8(ascii: ",") {
            index += 1
          } else if bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(object)
          } else {
            throw ParseError.unexpected(index)
          }
        }
      case UInt8(ascii: "["):
        index += 1
        var items: [JSONValue] = []
        skipSpace()
        if bytes[index] == UInt8(ascii: "]") {
          index += 1
          return .array(items)
        }
        while true {
          skipSpace()
          items.append(try value())
          skipSpace()
          if bytes[index] == UInt8(ascii: ",") {
            index += 1
          } else if bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items)
          } else {
            throw ParseError.unexpected(index)
          }
        }
      case UInt8(ascii: "\""):
        return .string(try string())
      case UInt8(ascii: "t"):
        index += 4
        return .bool(true)
      case UInt8(ascii: "f"):
        index += 5
        return .bool(false)
      case UInt8(ascii: "n"):
        index += 4
        return .null
      default:
        let start = index
        while index < bytes.count, "+-0123456789.eE".utf8.contains(bytes[index]) { index += 1 }
        guard index > start else { throw ParseError.unexpected(index) }
        return .number(String(decoding: bytes[start..<index], as: UTF8.self))
      }
    }

    mutating func string() throws -> String {
      index += 1
      var out = [UInt8]()
      while index < bytes.count {
        let byte = bytes[index]
        if byte == UInt8(ascii: "\"") {
          index += 1
          return String(decoding: out, as: UTF8.self)
        }
        if byte == UInt8(ascii: "\\") {
          index += 1
          guard index < bytes.count else { throw ParseError.badString(index) }
          let escape = bytes[index]
          index += 1
          switch escape {
          case UInt8(ascii: "n"): out.append(0x0A)
          case UInt8(ascii: "t"): out.append(0x09)
          case UInt8(ascii: "r"): out.append(0x0D)
          case UInt8(ascii: "b"): out.append(0x08)
          case UInt8(ascii: "f"): out.append(0x0C)
          case UInt8(ascii: "u"):
            var scalar = try hex4()
            if scalar >= 0x80 { sawEscapedNonASCII = true }
            if (0xD800..<0xDC00).contains(scalar), index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"),
              bytes[index + 1] == UInt8(ascii: "u")
            {
              index += 2
              let low = try hex4()
              scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
            }
            out.append(contentsOf: Array(String(Character(Unicode.Scalar(scalar) ?? "\u{FFFD}")).utf8))
          default: out.append(escape)
          }
        } else {
          out.append(byte)
          index += 1
        }
      }
      throw ParseError.badString(index)
    }

    mutating func hex4() throws -> UInt32 {
      guard index + 4 <= bytes.count, let value = UInt32(String(decoding: bytes[index..<index + 4], as: UTF8.self), radix: 16)
      else { throw ParseError.badString(index) }
      index += 4
      return value
    }
  }

  // MARK: Writing

  /// How a document is laid out, so a file written back looks as it did.
  struct Style: Equatable, Sendable {
    var indent = 1
    var sortKeys = true
    var escapeNonASCII = false
  }

  /// Python's `json.dumps(value, sort_keys=True, indent=indent, ensure_ascii=False)`
  /// by default; `style` follows a file that was written otherwise.
  static func write(_ value: JSONValue, indent: Int) -> String { write(value, style: Style(indent: indent)) }

  static func write(_ value: JSONValue, style: Style) -> String {
    var out = ""
    write(value, style: style, level: 0, into: &out)
    return out
  }

  /// Whether every object in `value` has its keys in code-point order.
  static func hasSortedKeys(_ value: JSONValue) -> Bool {
    switch value {
    case .object(let object):
      return object.keys == object.keys.sorted(by: codePointLess) && object.keys.allSatisfy { hasSortedKeys(object[$0]!) }
    case .array(let items): return items.allSatisfy(hasSortedKeys)
    default: return true
    }
  }

  static func codePointLess(_ a: String, _ b: String) -> Bool {
    Array(a.unicodeScalars.map(\.value)).lexicographicallyPrecedes(b.unicodeScalars.map(\.value))
  }

  private static func write(_ value: JSONValue, style: Style, level: Int, into out: inout String) {
    let indent = style.indent
    switch value {
    case .null: out += "null"
    case .bool(let flag): out += flag ? "true" : "false"
    case .number(let text): out += text
    case .string(let text): writeString(text, escapeNonASCII: style.escapeNonASCII, into: &out)
    case .array(let items):
      guard !items.isEmpty else { return out += "[]" }
      out += "["
      for (offset, item) in items.enumerated() {
        out += offset == 0 ? "\n" : ",\n"
        out += String(repeating: " ", count: indent * (level + 1))
        write(item, style: style, level: level + 1, into: &out)
      }
      out += "\n" + String(repeating: " ", count: indent * level) + "]"
    case .object(let object):
      guard !object.isEmpty else { return out += "{}" }
      out += "{"
      // Python sorts by code point; a file that isn't sorted keeps its order.
      let keys = style.sortKeys ? object.keys.sorted(by: codePointLess) : object.keys
      for (offset, key) in keys.enumerated() {
        out += offset == 0 ? "\n" : ",\n"
        out += String(repeating: " ", count: indent * (level + 1))
        writeString(key, escapeNonASCII: style.escapeNonASCII, into: &out)
        out += ": "
        write(object[key]!, style: style, level: level + 1, into: &out)
      }
      out += "\n" + String(repeating: " ", count: indent * level) + "}"
    }
  }

  private static func writeString(_ text: String, escapeNonASCII: Bool, into out: inout String) {
    out += "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      case "\u{08}": out += "\\b"
      case "\u{0C}": out += "\\f"
      default:
        if scalar.value < 0x20 {
          out += String(format: "\\u%04x", scalar.value)
        } else if escapeNonASCII && scalar.value >= 0x7F {
          // Python writes astral characters as a surrogate pair.
          for unit in String(scalar).utf16 { out += String(format: "\\u%04x", unit) }
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
  }
}

/// A JSON object that keeps its keys in the order they were read, so a file
/// not written in sorted order is written back the same way.
struct JSONObject: Equatable, Sendable, ExpressibleByDictionaryLiteral {
  private(set) var keys: [String] = []
  private var values: [String: JSONValue] = [:]

  init() {}

  init(dictionaryLiteral elements: (String, JSONValue)...) {
    for (key, value) in elements { self[key] = value }
  }

  var isEmpty: Bool { keys.isEmpty }

  subscript(key: String) -> JSONValue? {
    get { values[key] }
    set {
      if let newValue {
        if values[key] == nil { keys.append(key) }
        values[key] = newValue
      } else if values.removeValue(forKey: key) != nil {
        keys.removeAll { $0 == key }
      }
    }
  }
}
