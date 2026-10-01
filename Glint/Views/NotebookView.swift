import AppKit
import SwiftUI

/// A Jupyter notebook in the Files tab: its cells to read, edit and run.
/// Code cells run in a real kernel (`NotebookKernel`); Shift-Return runs a
/// cell, as in Jupyter. Markdown cells show rendered; double-click to edit.
struct NotebookView: View {
  @Bindable var document: NotebookDocument
  let project: URL
  var failed: (String, Error) -> Void
  @State private var editingMarkdown: String?

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Hairline()
      banner
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(document.notebook.cells) { cell in
              cellView(cell, proxy: proxy).id(cell.id)
            }
            addButtons(after: document.notebook.cells.last?.id)
          }
          .padding(16)
        }
      }
    }
    .background(Color(nsColor: Theme.shared.editorBackground))
  }

  // MARK: Toolbar and banners

  private var toolbar: some View {
    HStack(spacing: 10) {
      Text(document.fileName).font(.code(.body)).fontWeight(.semibold)
      if document.hasUnsavedChanges { Circle().fill(.secondary).frame(width: 6, height: 6) }
      Spacer()
      kernelStatus
      Button("Run All") { document.runAll(project: project) }
        .disabled(document.notebook.cells.allSatisfy { $0.kind != .code })
        .help("Run every code cell, top to bottom")
      if document.kernel.state == .busy {
        Button("Interrupt", action: document.kernel.interrupt).help("Stop the running cell")
      }
      Menu {
        Button("Restart Kernel", action: document.kernel.restart)
          .disabled(document.kernel.state == .stopped)
        Button("Clear All Outputs", action: document.clearOutputs)
      } label: {
        Image(systemName: "ellipsis")
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
    }
    .controlSize(.small)
    .font(.app(.callout))
    .padding(.horizontal, 12)
    .frame(height: 32)
  }

  private var kernelStatus: some View {
    let (text, color): (String, Color) =
      switch document.kernel.state {
      case .stopped: ("Kernel off", .secondary)
      case .starting: ("Starting\u{2026}", .secondary)
      case .ready: ("Idle", Color(nsColor: Theme.shared.createdLabel))
      case .busy: ("Busy", Color(nsColor: Theme.shared.modified))
      case .needsSetup: ("No Jupyter", Color(nsColor: Theme.shared.deletedLabel))
      case .settingUp: ("Setting up\u{2026}", .secondary)
      case .failed: ("Stopped", Color(nsColor: Theme.shared.deletedLabel))
      }
    return HStack(spacing: 5) {
      Circle().fill(color).frame(width: 7, height: 7)
      Text(text).foregroundStyle(.secondary)
    }
    .help(document.kernel.python.map { "Python: \($0.path)" } ?? "Starts when you run a cell")
  }

  @ViewBuilder private var banner: some View {
    switch document.kernel.state {
    case .needsSetup:
      notice(
        "Running cells needs a Python with Jupyter. Glint can make one for notebooks (with uv if you have it); "
          + "or pick your own in Settings, General.", action: "Set Up Python"
      ) {
        Task {
          do { try await document.setUpKernel(project: project) } catch { failed("Couldn't set up Python", error) }
        }
      }
    case .settingUp:
      notice("Setting up Python for notebooks. The first time takes a minute.", action: nil) {}
    case .failed(let message):
      notice(message, action: "Try Again") { document.kernel.restart() }
    default:
      EmptyView()
    }
    if document.hasConflict {
      notice("\(document.fileName) changed on disk while you were editing it. Autosave is paused.", action: "Use Theirs") {
        document.useTheirs()
      }
      .overlay(alignment: .trailing) {
        Button("Keep Mine") {
          do { try document.keepMine() } catch { failed("Couldn't save \(document.fileName)", error) }
        }
        .controlSize(.small)
        .padding(.trailing, 110)
      }
    } else if let note = document.note {
      Text(note).font(.app(.caption)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 4)
    }
  }

  private func notice(_ text: String, action: String?, perform: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
      Text(text).lineLimit(3)
      Spacer()
      if let action { Button(action, action: perform) }
    }
    .font(.app(.callout))
    .controlSize(.small)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.themeAccent.opacity(0.08))
  }

  // MARK: Cells

  private func cellView(_ cell: Notebook.Cell, proxy: ScrollViewProxy) -> some View {
    HStack(alignment: .top, spacing: 8) {
      gutter(cell)
      VStack(alignment: .leading, spacing: 6) {
        switch cell.kind {
        case .code:
          editor(cell, language: .python, proxy: proxy)
          ForEach(Array(cell.outputs.enumerated()), id: \.offset) { _, output in
            OutputView(output: output)
          }
        case .markdown where editingMarkdown != cell.id:
          MarkdownBlock(text: cell.source.isEmpty ? "*Empty. Double-click to write.*" : cell.source)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { editingMarkdown = cell.id }
        case .markdown:
          editor(cell, language: .markdown, proxy: proxy)
        case .raw:
          editor(cell, language: nil, proxy: proxy)
        }
      }
    }
    .padding(8)
    .background(
      RoundedRectangle(cornerRadius: 6)
        .strokeBorder(document.running.contains(cell.id) ? Color.themeAccent : Color(nsColor: ZedPalette.borderVariant), lineWidth: 1)
    )
    .contextMenu { menu(cell) }
  }

  private func gutter(_ cell: Notebook.Cell) -> some View {
    VStack(spacing: 4) {
      if cell.kind == .code {
        Button {
          document.run(cell.id, project: project)
        } label: {
          Image(systemName: document.running.contains(cell.id) ? "hourglass" : "play.fill").hitTarget()
        }
        .buttonStyle(.borderless)
        .help("Run this cell (Shift-Return)")
        Text(document.running.contains(cell.id) ? "[*]" : cell.executionCount.map { "[\($0)]" } ?? "[ ]")
          .font(.code(.caption))
          .foregroundStyle(.secondary)
      } else {
        Text(cell.kind == .markdown ? "M\u{2193}" : "raw").font(.code(.caption)).foregroundStyle(.tertiary)
      }
    }
    .frame(width: 40)
  }

  private func editor(_ cell: Notebook.Cell, language: SyntaxLanguage?, proxy: ScrollViewProxy) -> some View {
    let lines = max(1, cell.source.components(separatedBy: "\n").count)
    return CodeEditor(
      text: Binding(get: { cell.source }, set: { document.setSource($0, of: cell.id) }),
      language: language, firstLine: 1, fitsContent: true, showsLineNumbers: false, focusesOnAppear: false,
      onShiftReturn: { shiftReturn(in: cell, proxy: proxy) }
    )
    .frame(height: CGFloat(lines) * DiffMetrics.lineHeight + 18)
    .clipShape(RoundedRectangle(cornerRadius: 4))
  }

  /// Runs a code cell or shows a markdown one, then moves on, adding a cell
  /// at the end as Jupyter does.
  private func shiftReturn(in cell: Notebook.Cell, proxy: ScrollViewProxy) {
    if cell.kind == .code { document.run(cell.id, project: project) }
    if editingMarkdown == cell.id { editingMarkdown = nil }
    let cells = document.notebook.cells
    guard let index = cells.firstIndex(where: { $0.id == cell.id }) else { return }
    let next = index + 1 < cells.count ? cells[index + 1].id : document.insertCell(.code, after: cell.id)
    withAnimation(Motion.reveal) { proxy.scrollTo(next, anchor: .top) }
  }

  @ViewBuilder private func menu(_ cell: Notebook.Cell) -> some View {
    if cell.kind == .code { Button("Run Cell") { document.run(cell.id, project: project) } }
    if cell.kind == .markdown { Button("Edit Markdown") { editingMarkdown = cell.id } }
    Divider()
    Button("Insert Code Cell Below") { _ = document.insertCell(.code, after: cell.id) }
    Button("Insert Markdown Cell Below") { _ = document.insertCell(.markdown, after: cell.id) }
    Divider()
    Picker("Cell Type", selection: Binding(get: { cell.kind }, set: { document.setKind($0, of: cell.id) })) {
      Text("Code").tag(Notebook.CellKind.code)
      Text("Markdown").tag(Notebook.CellKind.markdown)
      Text("Raw").tag(Notebook.CellKind.raw)
    }
    Button("Move Up") { document.moveCell(cell.id, by: -1) }
    Button("Move Down") { document.moveCell(cell.id, by: 1) }
    Divider()
    Button("Delete Cell", role: .destructive) { document.deleteCell(cell.id) }
  }

  private func addButtons(after cellID: String?) -> some View {
    HStack(spacing: 8) {
      Button("+ Code") { _ = document.insertCell(.code, after: cellID) }
      Button("+ Markdown") {
        editingMarkdown = document.insertCell(.markdown, after: cellID)
      }
    }
    .buttonStyle(.borderless)
    .font(.app(.callout))
    .padding(.leading, 48)
  }
}

/// One output of a code cell.
private struct OutputView: View {
  let output: Notebook.Output

  var body: some View {
    Group {
      if let data = output.image, let image = NSImage(data: data) {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: min(image.size.width, 900), alignment: .leading)
      } else if output.kind != .error, output.kind != .stream, let markdown = output.markdown {
        MarkdownBlock(text: markdown)
      } else if let text = output.text ?? output.html.map(Self.stripTags) {
        Text(Self.capped(text))
          .font(.code(.callout))
          .foregroundStyle(output.isError ? Color(nsColor: Theme.shared.deletedLabel) : .primary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(.leading, 4)
  }

  /// Huge outputs stop at 2,000 lines; the notebook keeps them all.
  static func capped(_ text: String) -> String {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count > 2_000 else { return text }
    return lines.prefix(2_000).joined(separator: "\n") + "\n\u{2026} \(lines.count - 2_000) more lines"
  }

  static func stripTags(_ html: String) -> String {
    html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  }
}

/// Markdown as a notebook shows it: headings, lists, code blocks, and
/// inline styling.
struct MarkdownBlock: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
        switch block {
        case .heading(let level, let line):
          Text(inline(line)).font(.app(level == 1 ? .title2 : level == 2 ? .title3 : .headline))
        case .code(let code):
          Text(code)
            .font(.code(.callout))
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
        case .bullet(let line):
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\u{2022}").foregroundStyle(.secondary)
            Text(inline(line))
          }
        case .paragraph(let line):
          Text(inline(line))
        }
      }
    }
    .font(.app(.body))
    .textSelection(.enabled)
  }

  enum Block {
    case heading(Int, String)
    case code(String)
    case bullet(String)
    case paragraph(String)
  }

  static func blocks(_ text: String) -> [Block] {
    var blocks: [Block] = []
    var code: [String]?
    var paragraph: [String] = []
    func flush() {
      if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
      paragraph = []
    }
    for line in text.components(separatedBy: "\n") {
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        if let lines = code {
          blocks.append(.code(lines.joined(separator: "\n")))
          code = nil
        } else {
          flush()
          code = []
        }
        continue
      }
      if code != nil {
        code?.append(line)
        continue
      }
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty {
        flush()
      } else if let level = trimmed.firstIndex(where: { $0 != "#" }).map({ trimmed.distance(from: trimmed.startIndex, to: $0) }),
        level > 0, level <= 6, trimmed.dropFirst(level).hasPrefix(" ")
      {
        flush()
        blocks.append(.heading(level, String(trimmed.dropFirst(level + 1))))
      } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
        flush()
        blocks.append(.bullet(String(trimmed.dropFirst(2))))
      } else {
        paragraph.append(trimmed)
      }
    }
    if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
    flush()
    return blocks
  }

  private func inline(_ text: String) -> AttributedString {
    (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
  }
}
