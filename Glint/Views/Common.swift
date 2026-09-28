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
@MainActor
struct StatusMark {
  let letter: String
  let color: NSColor
  let label: String

  init(_ kind: ChangedFile.Kind) {
    switch kind {
    case .added: (letter, color, label) = ("A", Theme.shared.added, "Added")
    case .modified: (letter, color, label) = ("M", .systemOrange, "Modified")
    case .deleted: (letter, color, label) = ("D", Theme.shared.removed, "Deleted")
    case .renamed: (letter, color, label) = ("R", .systemBlue, "Renamed")
    case .typeChanged: (letter, color, label) = ("T", .systemOrange, "Type changed")
    case .untracked: (letter, color, label) = ("U", Theme.shared.added, "Untracked")
    case .conflicted: (letter, color, label) = ("!", .systemRed, "Conflicted")
    }
  }

  init(_ status: FileChange.Status) {
    switch status {
    case .added: (letter, color, label) = ("A", Theme.shared.added, "Added")
    case .deleted: (letter, color, label) = ("D", Theme.shared.removed, "Deleted")
    case .modified: (letter, color, label) = ("M", .systemOrange, "Modified")
    case .renamed: (letter, color, label) = ("R", .systemBlue, "Renamed")
    case .copied: (letter, color, label) = ("C", .systemBlue, "Copied")
    case .typeChanged: (letter, color, label) = ("T", .systemOrange, "Type changed")
    }
  }

  static let size: CGFloat = 16
  static let radius: CGFloat = 3
  static let tint: CGFloat = 0.15
  /// Fixed, like the tile it sits in: it's an icon, not text to read.
  static var font: NSFont { AppFont.ns(size: 10, weight: .semibold) }
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
      Text("+\(additions)").foregroundStyle(Color.added)
      Text("-\(deletions)").foregroundStyle(Color.removed)
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

/// ↑ and ↓ (and optionally Return) for a popover list, even while its search
/// field has focus. The monitor lives only while the popover is on screen.
private struct ArrowKeys: ViewModifier {
  let move: (Int) -> Void
  let choose: (() -> Void)?
  @State private var monitor: Any?

  func body(content: Content) -> some View {
    content
      .onAppear {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
          switch event.keyCode {
          case 125: move(1)
          case 126: move(-1)
          case 36, 76 where choose != nil: choose?()
          default: return event
          }
          return nil
        }
      }
      .onDisappear {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
      }
  }
}

extension View {
  func arrowKeys(move: @escaping (Int) -> Void, choose: (() -> Void)? = nil) -> some View {
    modifier(ArrowKeys(move: move, choose: choose))
  }

  /// The row Return will pick, in a popover list.
  func highlighted(_ isOn: Bool) -> some View {
    listRowBackground(
      isOn ? RoundedRectangle(cornerRadius: 5).fill(Color.themeAccent.opacity(0.2)).padding(.horizontal, 6) : nil)
  }
}
