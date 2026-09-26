import SwiftUI

struct RootView: View {
  @State private var session = RepositorySession()
  /// This window's terminals, one per repository, alive while hidden.
  @State private var terminals = TerminalStore()

  var body: some View {
    content
      .navigationTitle(title)
      .focusedSceneValue(\.session, session)
      .background(KeyMonitor(handle: session.handleKey))
      .onAppear { session.restoreLastRepository() }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        session.refresh()
      }
      .confirmationDialog(
        discardTitle,
        isPresented: Binding(
          get: { session.pendingDiscard != nil },
          set: { if !$0 { session.pendingDiscard = nil } }),
        titleVisibility: .visible
      ) {
        Button("Discard", role: .destructive, action: session.confirmDiscard)
        Button("Cancel", role: .cancel) {}
      } message: {
        Text(discardMessage)
      }
      .alert(
        "That didn't work",
        isPresented: Binding(
          get: { session.alertMessage != nil },
          set: { if !$0 { session.alertMessage = nil } })
      ) {
        Button("OK") {}
      } message: {
        Text(session.alertMessage ?? "")
      }
  }

  @ViewBuilder private var content: some View {
    switch session.phase {
    case .closed(let message):
      WelcomeView(message: message, open: session.chooseRepository)
    case .opening:
      Color.clear
    case .ready:
      NavigationSplitView {
        SidebarView(session: session)
          .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 480)
      } detail: {
        Group {
          if session.isTerminalShown, let folder = session.repositoryURL {
            VSplitView {
              DiffPane(session: session)
                .frame(minHeight: 160)
              TerminalPanel(folder: folder, store: terminals)
                .frame(minHeight: 100, idealHeight: 240)
            }
          } else {
            DiffPane(session: session)
          }
        }
        .modifier(DiffToolbar(session: session))
      }
      .toolbar(removing: .title)
    }
  }

  private var discardTitle: String {
    guard let files = session.pendingDiscard else { return "" }
    return files.count == 1 ? "Discard changes to \(files[0].fileName)?" : "Discard \(files.count) changes?"
  }

  private var discardMessage: String {
    let untracked = session.pendingDiscard?.contains { $0.kind == .untracked } ?? false
    return untracked
      ? "Edits to tracked files can't be undone. New files go to the Trash."
      : "This can't be undone."
  }

  /// For the Window menu and Mission Control; the toolbar shows
  /// `ProjectTitle` instead.
  private var title: String {
    session.projectURL?.lastPathComponent ?? "Adit"
  }
}

private struct WelcomeView: View {
  let message: String?
  let open: () -> Void

  var body: some View {
    VStack(spacing: 14) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
      Text("Adit")
        .font(.system(size: 34, weight: .semibold, design: .rounded))
      Text("A way in to every change.")
        .foregroundStyle(.secondary)
      Button("Open a Repository…", action: open)
        .keyboardShortcut(.defaultAction)
        .controlSize(.large)
        .padding(.top, 8)
      Text("Pick the folder that contains .git. You only have to do this once.")
        .font(.callout)
        .foregroundStyle(.secondary)
      if let message {
        Text(message)
          .font(.callout)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
      }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// The project switcher on the left, the terminal and layout controls on the
/// right. With no title there's no flexible space to push them apart, so the
/// toolbar needs a spacer, and it must sit on the detail column: on the whole
/// split view the spacer does nothing. Before macOS 26 there's no spacer and
/// the controls sit beside the switcher.
private struct DiffToolbar: ViewModifier {
  @Bindable var session: RepositorySession

  func body(content: Content) -> some View {
    if #available(macOS 26, *) {
      content.toolbar {
        ToolbarItem(placement: .navigation) { ProjectTitle(session: session) }
        ToolbarSpacer(.flexible)
        controls
      }
    } else {
      content.toolbar {
        ToolbarItem(placement: .navigation) { ProjectTitle(session: session) }
        controls
      }
    }
  }

  @ToolbarContentBuilder private var controls: some ToolbarContent {
    ToolbarItem {
      Button {
        session.isTerminalShown.toggle()
      } label: {
        Label("Terminal", systemImage: "apple.terminal")
      }
      .help(AppCommand.showTerminal.hint(session.isTerminalShown ? "Hide the terminal" : "Show the terminal"))
    }
    ToolbarItem {
      Picker("Layout", selection: $session.layout) {
        Text("Unified").tag(DiffLayout.unified)
        Text("Split").tag(DiffLayout.split)
      }
      .pickerStyle(.segmented)
      .help(AppCommand.toggleLayout.hint("Switch between unified and split diffs"))
    }
  }
}
