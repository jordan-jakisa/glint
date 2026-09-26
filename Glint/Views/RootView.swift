import SwiftUI

struct RootView: View {
  @State private var session = RepositorySession()
  @Environment(\.openSettings) private var openSettings

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
        session.alert?.title ?? "",
        isPresented: Binding(
          get: { session.alert != nil },
          set: { if !$0 { session.alert = nil } }),
        presenting: session.alert
      ) { alert in
        if alert.opensSettings {
          Button("Open Settings") { openSettings() }
            .keyboardShortcut(.defaultAction)
          Button("Not Now", role: .cancel) {}
        } else {
          Button("OK") {}
            .keyboardShortcut(.defaultAction)
          if let details = alert.details {
            Button("Copy Details") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(details, forType: .string)
            }
          }
        }
      } message: { alert in
        Text(alert.message)
      }
  }

  @ViewBuilder private var content: some View {
    switch session.phase {
    case .closed(let message):
      if OnboardingView.isDone || message != nil {
        WelcomeView(message: message, open: session.chooseRepository)
      } else {
        OnboardingView(open: session.chooseRepository)
      }
    case .opening:
      Color.clear
    case .ready:
      NavigationSplitView {
        SidebarView(session: session)
          .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 480)
      } detail: {
        DiffAndTerminal(session: session)
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
    session.projectURL?.lastPathComponent ?? "Glint"
  }
}

private struct WelcomeView: View {
  let message: String?
  let open: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 112, height: 112)
        .accessibilityHidden(true)
      Text("Glint")
        .font(.largeTitle.weight(.semibold))
      Text("Every change, at a glance.")
        .foregroundStyle(.secondary)
      Button(AppCommand.openRepository.title, action: open)
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

/// The diff, with the terminal under it when it's shown. The diff keeps one
/// place in the view tree, so showing or hiding the terminal never rebuilds it
/// and your scroll position stays put.
private struct DiffAndTerminal: View {
  let session: RepositorySession
  @AppStorage("terminalHeight") private var terminalHeight = 240.0
  @State private var dragStart: Double?

  var body: some View {
    GeometryReader { geometry in
      VStack(spacing: 0) {
        DiffPane(session: session)
          .frame(maxHeight: .infinity)
        if session.isTerminalShown, let folder = session.repositoryURL {
          divider(in: geometry.size.height)
          TerminalPanel(folder: folder, store: session.terminals) { session.isTerminalShown = false }
            .frame(height: clamped(terminalHeight, in: geometry.size.height))
        }
      }
    }
  }

  /// Drag to resize. The height is remembered between launches.
  private func divider(in total: Double) -> some View {
    Divider()
      .padding(.vertical, 3)
      .contentShape(Rectangle())
      .padding(.vertical, -3)
      .onHover { inside in
        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
      }
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { drag in
            let start = dragStart ?? clamped(terminalHeight, in: total)
            dragStart = start
            terminalHeight = clamped(start - drag.translation.height, in: total)
          }
          .onEnded { _ in dragStart = nil })
  }

  /// At least 100 pt of terminal, and at least 160 pt of diff above it.
  private func clamped(_ height: Double, in total: Double) -> Double {
    max(100, min(height, total - 160))
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
