import SwiftUI

/// Shared look for every diff row.
enum DiffStyle {
  static let font = Font.system(size: 12, design: .monospaced)
  /// Advance width of one digit in `font`, for sizing the gutters.
  static let digitWidth: CGFloat = 7.3

  static func gutterWidth(digits: Int) -> CGFloat {
    CGFloat(digits) * digitWidth + 12
  }

  static func background(_ kind: DiffLine.Kind?) -> Color {
    switch kind {
    case .addition: Color.green.opacity(0.14)
    case .deletion: Color.red.opacity(0.14)
    case .context, .noNewline: .clear
    case nil: Color.secondary.opacity(0.06)
    }
  }

  static func gutterBackground(_ kind: DiffLine.Kind?) -> Color {
    switch kind {
    case .addition: Color.green.opacity(0.22)
    case .deletion: Color.red.opacity(0.22)
    case .context, .noNewline: Color.secondary.opacity(0.05)
    case nil: Color.secondary.opacity(0.08)
    }
  }

  static func marker(_ kind: DiffLine.Kind) -> String {
    switch kind {
    case .addition: "+"
    case .deletion: "-"
    case .context, .noNewline: " "
    }
  }
}

struct DiffRowView: View {
  let row: DiffRow
  let gutterWidth: CGFloat
  let toggleCollapsed: (Int) -> Void

  var body: some View {
    switch row.content {
    case .fileHeader(let file, let collapsed):
      FileHeaderRow(file: file, collapsed: collapsed) { toggleCollapsed(file.id) }
    case .note(let text):
      Text(text)
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    case .hunkHeader(let hunk):
      Text(hunk.header)
        .font(DiffStyle.font)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08))
    case .line(let line):
      UnifiedLineRow(line: line, gutterWidth: gutterWidth)
    case .split(let pair):
      SplitLineRow(row: pair, gutterWidth: gutterWidth)
    }
  }
}

private struct FileHeaderRow: View {
  let file: FileChange
  let collapsed: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      HStack(spacing: 8) {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(collapsed ? 0 : 90))
          .frame(width: 12)
        StatusBadge(status: file.status)
        Text(title)
          .font(DiffStyle.font.weight(.semibold))
          .lineLimit(1)
          .truncationMode(.head)
        Spacer(minLength: 12)
        if file.additions > 0 {
          Text("+\(file.additions)").foregroundStyle(.green)
        }
        if file.deletions > 0 {
          Text("-\(file.deletions)").foregroundStyle(.red)
        }
      }
      .font(DiffStyle.font)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(.bar)
    .overlay(alignment: .top) { Divider() }
    .overlay(alignment: .bottom) { Divider() }
    .help(collapsed ? "Expand file (O)" : "Collapse file (O)")
  }

  private var title: String {
    if let oldPath = file.oldPath, let newPath = file.newPath, oldPath != newPath {
      return "\(oldPath) → \(newPath)"
    }
    return file.path
  }
}

private struct StatusBadge: View {
  let status: FileChange.Status

  var body: some View {
    Text(letter)
      .font(.system(size: 10, weight: .bold, design: .monospaced))
      .foregroundStyle(color)
      .frame(width: 16, height: 16)
      .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
      .help(label)
  }

  private var letter: String {
    switch status {
    case .added: "A"
    case .deleted: "D"
    case .modified: "M"
    case .renamed: "R"
    case .copied: "C"
    case .typeChanged: "T"
    }
  }

  private var label: String {
    switch status {
    case .added: "Added"
    case .deleted: "Deleted"
    case .modified: "Modified"
    case .renamed: "Renamed"
    case .copied: "Copied"
    case .typeChanged: "Type changed"
    }
  }

  private var color: Color {
    switch status {
    case .added: .green
    case .deleted: .red
    case .modified, .typeChanged: .orange
    case .renamed, .copied: .blue
    }
  }
}

private struct LineNumber: View {
  let number: Int?
  let width: CGFloat

  var body: some View {
    Text(number.map(String.init) ?? "")
      .foregroundStyle(.secondary)
      .frame(width: width, alignment: .trailing)
      .padding(.trailing, 6)
  }
}

private struct UnifiedLineRow: View {
  let line: DiffLine
  let gutterWidth: CGFloat

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      HStack(alignment: .top, spacing: 0) {
        LineNumber(number: line.oldNumber, width: gutterWidth)
        LineNumber(number: line.newNumber, width: gutterWidth)
      }
      .frame(maxHeight: .infinity, alignment: .top)
      .background(DiffStyle.gutterBackground(line.kind))
      LineText(line: line)
    }
    .font(DiffStyle.font)
    .fixedSize(horizontal: false, vertical: true)
    .background(DiffStyle.background(line.kind))
  }
}

private struct SplitLineRow: View {
  let row: SplitRow
  let gutterWidth: CGFloat

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      side(row.left, number: row.left?.oldNumber)
      Divider()
      side(row.right, number: row.right?.newNumber)
    }
    .font(DiffStyle.font)
    .fixedSize(horizontal: false, vertical: true)
  }

  private func side(_ line: DiffLine?, number: Int?) -> some View {
    HStack(alignment: .top, spacing: 0) {
      LineNumber(number: number, width: gutterWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(DiffStyle.gutterBackground(line?.kind))
      if let line {
        LineText(line: line)
      } else {
        Color.clear.frame(maxWidth: .infinity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(line.map { DiffStyle.background($0.kind) } ?? DiffStyle.background(nil))
  }
}

private struct LineText: View {
  let line: DiffLine

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      Text(DiffStyle.marker(line.kind))
        .foregroundStyle(.secondary)
        .frame(width: 16)
      // An empty Text has no height; a space keeps blank lines one line tall.
      Text(line.text.isEmpty ? " " : line.text)
        .foregroundStyle(line.kind == .noNewline ? .secondary : .primary)
        .italic(line.kind == .noNewline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 8)
    }
    .padding(.vertical, 1)
  }
}
