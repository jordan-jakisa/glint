import SwiftUI

/// Scaffold placeholder. Replaced in v0.1 step 1 by the repo picker and
/// commit list. See docs/plans/v0.1-diff-viewer.md.
struct ContentView: View {
  var body: some View {
    VStack(spacing: 8) {
      Text("Adit")
        .font(.system(size: 34, weight: .semibold, design: .rounded))
      Text("A way in to every change.")
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

#Preview {
  ContentView()
}
