import SwiftUI

/// A small spinner that appears only once the work has taken 150 ms, so fast
/// work never flashes one. Its space is always kept, so nothing shifts when it
/// shows.
struct DelayedSpinner: View {
  let isActive: Bool
  @State private var isShown = false

  var body: some View {
    ProgressView()
      .controlSize(.small)
      .opacity(isShown ? 1 : 0)
      .task(id: isActive) {
        guard isActive else {
          isShown = false
          return
        }
        try? await Task.sleep(for: .milliseconds(150))
        if !Task.isCancelled { isShown = true }
      }
      .accessibilityHidden(!isShown)
  }
}

/// The letter and colour for a file's status, shared by the file list and the
/// diff's file headers so the two always agree.
struct StatusMark {
  let letter: String
  let color: NSColor
  let label: String

  init(_ kind: ChangedFile.Kind) {
    switch kind {
    case .added: (letter, color, label) = ("A", .systemGreen, "Added")
    case .modified: (letter, color, label) = ("M", .systemOrange, "Modified")
    case .deleted: (letter, color, label) = ("D", .systemRed, "Deleted")
    case .renamed: (letter, color, label) = ("R", .systemBlue, "Renamed")
    case .typeChanged: (letter, color, label) = ("T", .systemOrange, "Type changed")
    case .untracked: (letter, color, label) = ("U", .systemGreen, "Untracked")
    case .conflicted: (letter, color, label) = ("!", .systemRed, "Conflicted")
    }
  }

  init(_ status: FileChange.Status) {
    switch status {
    case .added: (letter, color, label) = ("A", .systemGreen, "Added")
    case .deleted: (letter, color, label) = ("D", .systemRed, "Deleted")
    case .modified: (letter, color, label) = ("M", .systemOrange, "Modified")
    case .renamed: (letter, color, label) = ("R", .systemBlue, "Renamed")
    case .copied: (letter, color, label) = ("C", .systemBlue, "Copied")
    case .typeChanged: (letter, color, label) = ("T", .systemOrange, "Type changed")
    }
  }

  static let size: CGFloat = 16
  static let radius: CGFloat = 3
  static let tint: CGFloat = 0.15
  static var font: NSFont { .monospacedSystemFont(ofSize: 10, weight: .bold) }
}

/// A file's status as a small tinted tile, the same one the diff draws.
struct ChangeKindBadge: View {
  let kind: ChangedFile.Kind

  var body: some View {
    let mark = StatusMark(kind)
    Text(mark.letter)
      .font(Font(StatusMark.font))
      .foregroundStyle(Color(nsColor: mark.color))
      .frame(width: StatusMark.size, height: StatusMark.size)
      .background(
        Color(nsColor: mark.color).opacity(StatusMark.tint),
        in: RoundedRectangle(cornerRadius: StatusMark.radius))
      .help(mark.label)
      .accessibilityLabel(mark.label)
  }
}

/// `+12 -3`, in the system diff colours, with digits that don't change width
/// as the counts change.
struct ChangeStats: View {
  let additions: Int
  let deletions: Int

  var body: some View {
    HStack(spacing: 4) {
      Text("+\(additions)").foregroundStyle(.green)
      Text("-\(deletions)").foregroundStyle(.red)
    }
    .monospacedDigit()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(additions) added, \(deletions) removed")
  }
}

extension View {
  /// At least 22 pt to click, for small icon-only buttons.
  func hitTarget() -> some View {
    frame(minWidth: 22, minHeight: 22).contentShape(Rectangle())
  }
}
