import SwiftUI

/// A conflicted file in place of its diff: each conflict boxed, your side
/// (current) over theirs (incoming), with buttons to keep either or both.
/// The text around them shows dimmed, trimmed to a few lines each side.
struct ConflictView: View {
  let session: RepositorySession
  let path: String

  /// Lines of context kept next to each conflict.
  nonisolated private static let contextLines = 3

  private struct ReloadKey: Hashable {
    let path: String
    let version: Int
  }

  var body: some View {
    let document = session.conflictDocument?.path == path ? session.conflictDocument : nil
    VStack(spacing: 0) {
      header(document)
      Hairline()
      if let document {
        content(document)
      } else {
        // Reading a file takes a frame; a spinner would only flicker.
        Color.clear
      }
    }
    // Rereads the file when you pick it and whenever the watcher reloads it.
    .task(id: ReloadKey(path: path, version: session.rowsVersion)) {
      await session.loadConflict(path)
    }
  }

  private var fileName: String { (path as NSString).lastPathComponent }

  private func header(_ document: ConflictDocument?) -> some View {
    HStack(alignment: .center, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(path)
          .font(.app(.headline))
          .lineLimit(1)
          .truncationMode(.head)
          .textSelection(.enabled)
        HStack(spacing: 12) {
          Text("Conflicted")
          if let count = document?.regions.count, count > 0 {
            Text(count == 1 ? "1 conflict" : "\(count) conflicts")
          }
        }
        .font(.app(.callout))
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 12)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  @ViewBuilder private func content(_ document: ConflictDocument) -> some View {
    if document.content == nil {
      EmptyState(
        "Can't show this conflict", systemImage: "exclamationmark.triangle",
        description: Text(
          "\(fileName) isn't text Glint can read, or one side deleted it. Sort it out in the terminal, then stage it."))
    } else if document.regions.isEmpty {
      EmptyState {
        Label("No conflicts left", systemImage: "checkmark.circle")
      } description: {
        Text("All conflicts resolved. Stage the file to mark it resolved.")
      } actions: {
        Button("Stage File") { session.setStaged(path, true) }
      }
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(Self.segments(of: document)) { segment in
            switch segment.kind {
            case .context(let start, let lines):
              ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
                CodeLine(number: start + offset + 1, text: line)
                  .foregroundStyle(.tertiary)
              }
            case .gap(let count):
              Text(count == 1 ? "\u{2026}1 line\u{2026}" : "\u{2026}\(count) lines\u{2026}")
                .font(.app(.caption))
                .foregroundStyle(.tertiary)
                .padding(.leading, CodeLine.gutter + 8)
                .padding(.vertical, 4)
            case .region(let region):
              RegionBox(region: region, total: document.regions.count) { choice in
                session.resolveConflict(region, as: choice)
              }
            }
          }
        }
        .padding(.vertical, 8)
      }
    }
  }

  // MARK: Layout

  struct Segment: Identifiable {
    enum Kind {
      /// Lines outside any conflict, the first one at `start` (0-based).
      case context(start: Int, lines: [String])
      /// Context left out.
      case gap(Int)
      case region(ConflictRegion)
    }
    let id: Int
    let kind: Kind
  }

  /// The file as the view lays it out: each conflict, with a few lines of
  /// context each side and the long runs between them folded.
  nonisolated static func segments(of document: ConflictDocument) -> [Segment] {
    var segments: [Segment] = []
    func add(_ kind: Segment.Kind) { segments.append(Segment(id: segments.count, kind: kind)) }
    func context(_ range: Range<Int>) {
      guard !range.isEmpty else { return }
      add(.context(start: range.lowerBound, lines: Array(document.lines[range])))
    }

    var next = 0
    for (index, region) in document.regions.enumerated() {
      let run = next..<region.lines.lowerBound
      let keepsHead = index > 0 ? contextLines : 0
      if run.count <= keepsHead + contextLines + 1 {
        context(run)
      } else {
        context(run.lowerBound..<(run.lowerBound + keepsHead))
        add(.gap(run.count - keepsHead - contextLines))
        context((run.upperBound - contextLines)..<run.upperBound)
      }
      add(.region(region))
      next = region.lines.upperBound
    }
    let tail = next..<document.lines.count
    if tail.count <= contextLines + 1 {
      context(tail)
    } else {
      context(tail.lowerBound..<(tail.lowerBound + contextLines))
      add(.gap(tail.count - contextLines))
    }
    return segments
  }
}

/// One line of the file: its number in the gutter, then the text.
private struct CodeLine: View {
  static let gutter: CGFloat = 48
  let number: Int?
  let text: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(number.map(String.init) ?? "")
        .frame(width: Self.gutter, alignment: .trailing)
        .foregroundStyle(.tertiary)
      // An empty line still takes a line's height.
      Text(text.isEmpty ? " " : text)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .font(.code(.body))
    .padding(.trailing, 12)
  }
}

/// One conflict: what to keep, then both sides, current in the added
/// colour and incoming in blue, as in Zed.
private struct RegionBox: View {
  let region: ConflictRegion
  let total: Int
  let resolve: (ConflictChoice) -> Void

  var body: some View {
    let theme = Theme.shared
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text("Conflict \(region.index + 1) of \(total)")
          .font(.app(.callout))
          .foregroundStyle(.secondary)
        Spacer(minLength: 12)
        Button("Use Current") { resolve(.current) }
          .help("Keep your side, \(title("Current", region.currentLabel))")
        Button("Use Incoming") { resolve(.incoming) }
          .help("Keep their side, \(title("Incoming", region.incomingLabel))")
        Button("Use Both") { resolve(.both) }
          .help("Keep both, yours first")
      }
      .controlSize(.small)
      VStack(alignment: .leading, spacing: 0) {
        side(
          title("Current", region.currentLabel), lines: region.current,
          firstLine: region.lines.lowerBound + 2, color: Color(nsColor: theme.added))
        Hairline()
        side(
          title("Incoming", region.incomingLabel), lines: region.incoming,
          firstLine: incomingFirstLine, color: Color(nsColor: theme.incoming))
      }
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Hairline.color))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  /// Where the incoming lines start in the file, 1-based: past the opening
  /// marker, your side, the base section if any, and the separator.
  private var incomingFirstLine: Int {
    region.lines.lowerBound + 1 + region.current.count + (region.base.map { $0.count + 1 } ?? 0) + 2
  }

  private func title(_ side: String, _ label: String) -> String {
    label.isEmpty ? side : "\(side): \(label)"
  }

  private func side(_ title: String, lines: [String], firstLine: Int, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .font(.app(.caption))
        .fontWeight(.semibold)
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
      if lines.isEmpty {
        Text("Nothing on this side")
          .font(.app(.caption))
          .foregroundStyle(.tertiary)
          .padding(.leading, CodeLine.gutter + 8)
          .padding(.bottom, 4)
      } else {
        ForEach(Array(lines.enumerated()), id: \.offset) { offset, line in
          CodeLine(number: firstLine + offset, text: line)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(color.opacity(0.1))
  }
}
