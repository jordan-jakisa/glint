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
