import SwiftUI

/// Changes and History, as tabs, the way Zed's git panel splits them.
struct SidebarView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    VStack(spacing: 0) {
      Picker("View", selection: $session.tab) {
        Text(changesTitle).tag(RepositorySession.Tab.changes)
        Text("History").tag(RepositorySession.Tab.history)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      Divider()
      switch session.tab {
      case .changes: ChangesView(session: session)
      case .history: CommitListView(session: session)
      }
    }
    .onAppear { Timing.reportLaunchIfNeeded() }
  }

  private var changesTitle: String {
    let count = Set(session.status.staged.map(\.path) + session.status.unstaged.map(\.path)).count
    return count == 0 ? "Changes" : "Changes \(count)"
  }
}
