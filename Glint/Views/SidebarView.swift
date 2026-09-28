import SwiftUI

/// Changes and History, as tabs, the way Zed's git panel splits them. The
/// switch sits in the title bar beside the window buttons, so the list
/// starts right under it; in Minimal it's in the status line.
struct SidebarView: View {
  @Bindable var session: RepositorySession

  var body: some View {
    VStack(spacing: 0) {
      // Style Zed: the panel's own tab bar, as in Zed's git panel.
      if Theme.shared.isZed, !Theme.shared.isMinimal {
        ZedTabBar(session: session)
      }
      switch session.tab {
      case .changes: ChangesView(session: session)
      case .history: CommitListView(session: session)
      }
    }
    // Style Zed: the panel's own colour instead of the sidebar material.
    .background(Theme.shared.panelBackground.map { Color(nsColor: $0) } ?? .clear)
    .modifier(TabPickerToolbar(session: session))
    .onAppear { Timing.reportLaunchIfNeeded() }
  }
}

private struct TabPickerToolbar: ViewModifier {
  @Bindable var session: RepositorySession

  // Empty in Minimal rather than removed, so switching doesn't rebuild.
  func body(content: Content) -> some View {
    // Minimal has the status line, Style Zed the panel's tab bar.
    let minimal = Theme.shared.isMinimal || Theme.shared.isZed
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

/// Zed's git panel tabs: two halves of the panel's width, the inactive one
/// dimmed over the editor colour with a border under it, and Changes with
/// its count (render_tab_bar in git_panel.rs).
private struct ZedTabBar: View {
  @Bindable var session: RepositorySession

  var body: some View {
    HStack(spacing: 0) {
      tab(.changes, "Changes", count: changeCount)
      Hairline(axis: .vertical)
      tab(.history, "History", count: nil)
    }
    .frame(height: 32)
  }

  private var changeCount: Int {
    Set(session.status.staged.map(\.path) + session.status.unstaged.map(\.path)).count
  }

  private func tab(_ tab: RepositorySession.Tab, _ title: String, count: Int?) -> some View {
    let active = session.tab == tab
    return Button {
      session.tab = tab
    } label: {
      HStack(spacing: 4) {
        Text(title).foregroundStyle(active ? .primary : .secondary)
        if let count, count > 0 {
          Text("(\(count))").font(.app(.caption)).foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(active ? Color.clear : Color(nsColor: Theme.shared.editorBackground).opacity(0.6))
      .overlay(alignment: .bottom) {
        if !active { Hairline() }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .font(.app(.body))
    .accessibilityAddTraits(active ? .isSelected : [])
  }
}
