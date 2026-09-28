import SwiftUI

/// Changes and History, as tabs, the way Zed's git panel splits them. The
/// switch sits in the title bar beside the window buttons, so the list
/// starts right under it; in Minimal it's in the status line.
struct SidebarView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    Group {
      switch session.tab {
      case .changes: ChangesView(session: session)
      case .history: CommitListView(session: session)
      }
    }
    .modifier(TabPickerToolbar(session: session))
    .onAppear { Timing.reportLaunchIfNeeded() }
  }
}

private struct TabPickerToolbar: ViewModifier {
  @Bindable var session: RepositorySession

  func body(content: Content) -> some View {
    if Theme.shared.isMinimal {
      content
    } else if #available(macOS 26, *) {
      content.toolbar {
        ToolbarItem { picker }
          .sharedBackgroundVisibility(Theme.shared.usesLiquidGlass ? .automatic : .hidden)
      }
    } else {
      content.toolbar {
        ToolbarItem { picker }
      }
    }
  }

  private var picker: some View {
    Picker("View", selection: $session.tab) {
      Text("Changes").tag(RepositorySession.Tab.changes)
      Text("History").tag(RepositorySession.Tab.history)
    }
    .pickerStyle(.segmented)
    .labelsHidden()
  }
}
