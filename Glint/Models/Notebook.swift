import Foundation

/// A Jupyter notebook (nbformat 4). Reading keeps the whole document, so
/// writing changes only what you edited: everything Glint doesn't know
/// about (metadata, attachments, widget state) goes back untouched, in
/// Jupyter's own layout (sorted keys, one-space indent), so a save that
/// changes nothing changes no bytes.
struct Notebook: Equatable, Sendable {
  enum CellKind: String, Sendable { case code, markdown, raw }

  struct Cell: Identifiable, Equatable, Sendable {
    /// nbformat 4.5's cell id, or one made up for older notebooks (not saved).
    let id: String
    var kind: CellKind
    var source: String
    var outputs: [Output]
    var executionCount: Int?
    /// The cell as read, for the fields Glint doesn't touch.
    var raw: JSONValue
  }

  /// One output of a code cell, in nbformat's own terms.
  struct Output: Equatable, Sendable {
    enum Kind: String, Sendable { case stream, executeResult = "execute_result", displayData = "display_data", error }
    var kind: Kind
    var raw: JSONValue

    /// What a person reads: stream text, `text/plain`, an error's traceback.
    var text: String? {
      switch kind {
      case .stream: return Notebook.joined(raw["text"])
      case .error:
        let lines = raw["traceback"]?.array?.compactMap(\.string) ?? []
        let joined = lines.joined(separator: "\n")
        return ANSI.strip(joined.isEmpty ? "\(raw["ename"]?.string ?? ""): \(raw["evalue"]?.string ?? "")" : joined)
      case .executeResult, .displayData:
        return Notebook.joined(raw["data"]?["text/plain"])
      }
    }

    var isError: Bool { kind == .error || (kind == .stream && raw["name"]?.string == "stderr") }

    /// A PNG or JPEG image, decoded.
    var image: Data? {
      for type in ["image/png", "image/jpeg"] {
        if let encoded = Notebook.joined(raw["data"]?[type]) {
          return Data(base64Encoded: encoded.filter { !$0.isWhitespace })
        }
      }
      return nil
    }

    var markdown: String? { Notebook.joined(raw["data"]?["text/markdown"]) }
    var html: String? { Notebook.joined(raw["data"]?["text/html"]) }
  }

  var cells: [Cell]
  /// The document as read; `cells` replaces its `cells` when written.
  var raw: JSONValue

  /// The kernel the notebook asks for, like `python3`.
  var kernelName: String? { raw["metadata"]?["kernelspec"]?["name"]?.string }
  var language: String { raw["metadata"]?["language_info"]?["name"]?.string ?? raw["metadata"]?["kernelspec"]?["language"]?.string ?? "python" }

  init(data: Data) throws {
    let value = try JSONValue.parse(data)
    guard case .object(let object) = value, case .array(let cells)? = object["cells"] else {
      throw NotebookError.notANotebook
    }
    raw = value
    self.cells = cells.enumerated().map { index, cell in
      let kind = CellKind(rawValue: cell["cell_type"]?.string ?? "") ?? .raw
      return Cell(
        id: cell["id"]?.string ?? "cell-\(index)",
        kind: kind,
        source: Notebook.joined(cell["source"]) ?? "",
        outputs: (cell["outputs"]?.array ?? []).map {
          Output(kind: Output.Kind(rawValue: $0["output_type"]?.string ?? "") ?? .displayData, raw: $0)
        },
        executionCount: cell["execution_count"]?.int,
        raw: cell)
    }
  }

  /// A new, empty notebook for a language.
  static func empty(language: String = "python") -> Notebook {
    let json = """
      {"cells": [], "metadata": {"kernelspec": {"display_name": "Python 3", "language": "\(language)", "name": "python3"},
      "language_info": {"name": "\(language)"}}, "nbformat": 4, "nbformat_minor": 5}
      """
    return try! Notebook(data: Data(json.utf8))
  }

  /// The document as Jupyter would write it.
  func data() -> Data {
    var document = raw
    document["cells"] = .array(cells.map(Self.encode))
    return Data((JSONValue.write(document, indent: 1) + "\n").utf8)
  }

  private static func encode(_ cell: Cell) -> JSONValue {
    var value = cell.raw
    if case .null = value { value = .object([:]) }
    value["cell_type"] = .string(cell.kind.rawValue)
    value["source"] = lines(cell.source)
    if value["metadata"] == nil { value["metadata"] = .object([:]) }
    if cell.kind == .code {
      value["outputs"] = .array(cell.outputs.map(\.raw))
      value["execution_count"] = cell.executionCount.map { .number(Double($0)) } ?? .null
    } else {
      value["outputs"] = nil
      value["execution_count"] = nil
    }
    return value
  }

  /// nbformat's multiline string: a list of lines, each keeping its "\n".
  static func lines(_ text: String) -> JSONValue {
    guard !text.isEmpty else { return .array([]) }
    var lines: [JSONValue] = []
    var current = ""
    for character in text {
      current.append(character)
      if character == "\n" {
        lines.append(.string(current))
        current = ""
      }
    }
    if !current.isEmpty { lines.append(.string(current)) }
    return .array(lines)
  }

  /// A multiline string, as a list of lines or one string.
  static func joined(_ value: JSONValue?) -> String? {
    switch value {
    case .string(let text)?: return text
    case .array(let parts)?: return parts.compactMap(\.string).joined()
    default: return nil
    }
  }

  // MARK: Reading in a diff

  /// The notebook as text a person can read in a diff: each cell under a
  /// `# %% [kind]` marker, as in VS Code and Jupytext, its source as it is,
  /// and outputs summed up in one line each, so a re-run doesn't drown the
  /// change in base64.
  func readableText() -> String {
    var out: [String] = []
    for (index, cell) in cells.enumerated() {
      let count = cell.executionCount.map { " [\($0)]" } ?? ""
      out.append("# %% [\(cell.kind.rawValue)]\(count) cell \(index + 1)")
      out.append(cell.source.hasSuffix("\n") ? String(cell.source.dropLast()) : cell.source)
      for output in cell.outputs {
        out.append(Self.summary(output))
      }
      out.append("")
    }
    return out.joined(separator: "\n")
  }

  private static func summary(_ output: Output) -> String {
    switch output.kind {
    case .error:
      return "# >> error: \(output.raw["ename"]?.string ?? "") \(output.raw["evalue"]?.string ?? "")"
    case .stream:
      let text = (output.text ?? "").split(separator: "\n", omittingEmptySubsequences: false)
      let first = text.first.map(String.init) ?? ""
      return "# >> \(output.raw["name"]?.string ?? "stream"): \(first.prefix(120))\(text.count > 2 ? " (\(text.count - 1) lines)" : "")"
    case .executeResult, .displayData:
      if output.image != nil { return "# >> image" }
      let text = (output.text ?? "").split(separator: "\n").first.map(String.init) ?? ""
      return "# >> \(text.prefix(120))"
    }
  }
}

enum NotebookError: LocalizedError {
  case notANotebook
  var errorDescription: String? { "This isn't a Jupyter notebook Glint can read." }
}

/// Terminal colour codes, as in tracebacks.
enum ANSI {
  static func strip(_ text: String) -> String {
    text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
  }
}
