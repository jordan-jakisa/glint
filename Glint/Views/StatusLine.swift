import SwiftUI

/// Minimal mode's only chrome, along the bottom of the window like Zed's
/// status bar: the sidebar, the project, the sidebar's two tabs, where you
/// are, sync, and the diff and terminal toggles. Everything the toolbar
/// offers in Standard is here, so no command goes missing.
struct StatusLine: View {
  @Bindable var session: RepositorySession
  @Binding var columns: NavigationSplitViewVisibility

  var body: some View {
    HStack(spacing: 12) {
      Button {
        columns = columns == .detailOnly ? .all : .detailOnly
      } label: {
        Label("Sidebar", systemImage: "sidebar.left")
      }
      .help(columns == .detailOnly ? "Show the sidebar" : "Hide the sidebar")
      // Hosts the switcher popover, so ⌥⌘O works here too.
      ProjectTitle(session: session)
        .labelStyle(.titleAndIcon)
      HStack(spacing: 10) {
        tab(.changes, "Changes")
        tab(.history, "History")
      }
      BranchBar(session: session, isInStatusLine: true)
      LayoutToggle(session: session)
      Button {
        session.isTerminalShown.toggle()
      } label: {
        Label("Terminal", systemImage: "apple.terminal")
      }
      .help(AppCommand.showTerminal.hint(session.isTerminalShown ? "Hide the terminal" : "Show the terminal"))
    }
    .buttonStyle(.borderless)
    .labelStyle(.iconOnly)
    .font(.app(.callout))
    .padding(.horizontal, 10)
    .frame(height: 28)
  }

  private func tab(_ tab: RepositorySession.Tab, _ title: String) -> some View {
    Button(title) { session.tab = tab }
      .fontWeight(session.tab == tab ? .semibold : .regular)
      .foregroundStyle(session.tab == tab ? .primary : .secondary)
      .accessibilityAddTraits(session.tab == tab ? .isSelected : [])
  }
}

/// One icon that flips the diff between unified and split. The icon shows
/// the layout you're in.
struct LayoutToggle: View {
  @Bindable var session: RepositorySession

  var body: some View {
    let isSplit = session.layout == .split
    Button(action: session.toggleLayout) {
      Label(isSplit ? "Split diff" : "Unified diff", systemImage: isSplit ? "rectangle.split.2x1" : "rectangle")
    }
    .help(AppCommand.toggleLayout.hint(isSplit ? "Split diff, click for unified" : "Unified diff, click for split"))
  }
}
