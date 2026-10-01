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
  case object([String: JSONValue])

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

  static func parse(_ data: Data) throws -> JSONValue {
    var parser = Parser(bytes: Array(data))
    parser.skipSpace()
    let value = try parser.value()
    parser.skipSpace()
    guard parser.index == parser.bytes.count else { throw ParseError.trailing }
    return value
  }

  enum ParseError: Error { case unexpected(Int), trailing, badString(Int) }

  private struct Parser {
    let bytes: [UInt8]
    var index = 0

    mutating func skipSpace() {
      while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    mutating func value() throws -> JSONValue {
      guard index < bytes.count else { throw ParseError.unexpected(index) }
      switch bytes[index] {
      case UInt8(ascii: "{"):
        index += 1
        var object: [String: JSONValue] = [:]
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

  /// Python's `json.dumps(value, sort_keys=True, indent=indent, ensure_ascii=False)`.
  static func write(_ value: JSONValue, indent: Int) -> String {
    var out = ""
    write(value, indent: indent, level: 0, into: &out)
    return out
  }

  private static func write(_ value: JSONValue, indent: Int, level: Int, into out: inout String) {
    switch value {
    case .null: out += "null"
    case .bool(let flag): out += flag ? "true" : "false"
    case .number(let text): out += text
    case .string(let text): writeString(text, into: &out)
    case .array(let items):
      guard !items.isEmpty else { return out += "[]" }
      out += "["
      for (offset, item) in items.enumerated() {
        out += offset == 0 ? "\n" : ",\n"
        out += String(repeating: " ", count: indent * (level + 1))
        write(item, indent: indent, level: level + 1, into: &out)
      }
      out += "\n" + String(repeating: " ", count: indent * level) + "]"
    case .object(let object):
      guard !object.isEmpty else { return out += "{}" }
      out += "{"
      // Python sorts by code point.
      for (offset, key) in object.keys.sorted(by: { Array($0.unicodeScalars.map(\.value)).lexicographicallyPrecedes($1.unicodeScalars.map(\.value)) }).enumerated() {
        out += offset == 0 ? "\n" : ",\n"
        out += String(repeating: " ", count: indent * (level + 1))
        writeString(key, into: &out)
        out += ": "
        write(object[key]!, indent: indent, level: level + 1, into: &out)
      }
      out += "\n" + String(repeating: " ", count: indent * level) + "}"
    }
  }

  private static func writeString(_ text: String, into out: inout String) {
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
        } else {
          out.unicodeScalars.append(scalar)
        }
      }
    }
    out += "\""
  }
}
