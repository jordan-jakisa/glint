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

  // Empty in Minimal rather than removed, so switching doesn't rebuild.
  func body(content: Content) -> some View {
    let minimal = Theme.shared.isMinimal
    if #available(macOS 26, *) {
      content.toolbar {
        if !minimal {
          ToolbarItem { picker }
            .sharedBackgroundVisibility(Theme.shared.usesLiquidGlass ? .automatic : .hidden)
        }
      }
    } else {
      content.toolbar {
        if !minimal {
          ToolbarItem { picker }
        }
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
