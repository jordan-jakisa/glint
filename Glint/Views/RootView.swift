import SwiftUI

struct RootView: View {
  @State private var session = RepositorySession()
  @State private var columns: NavigationSplitViewVisibility =
    UserDefaults.standard.bool(forKey: "sidebarHidden") ? .detailOnly : .all
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
      .sheet(
        item: Binding(get: { session.editingHunk }, set: { session.editingHunk = $0 })
      ) { edit in
        HunkEditor(edit: edit, save: session.saveEdit) { session.editingHunk = nil }
          .font(.app(.body))
          .tint(.themeAccent)
          .themedTextLevels()
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
        } else if alert.canRetry {
          Button("Try Again") { session.retryAlertAction?() }
            .keyboardShortcut(.defaultAction)
          Button("Cancel", role: .cancel) {}
          if let details = alert.details {
            Button("Copy Details") {
              NSPasteboard.general.clearContents()
              NSPasteboard.general.setString(details, forType: .string)
            }
          }
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
      OpeningView(name: session.openingName)
    case .ready:
      NavigationSplitView(columnVisibility: $columns) {
        SidebarView(session: session)
          .modifier(FlatSidebarToggle())
          .navigationSplitViewColumnWidth(min: 240, ideal: 320, max: 480)
      } detail: {
        DiffAndTerminal(session: session)
          .background(Color(nsColor: Theme.shared.editorBackground))
          .modifier(DiffToolbar(session: session, columns: $columns))
          // SwiftUI keeps toolbar items' glass as first built; flipping the
          // setting rebuilds the column. Rare, so losing the diff's scroll
          // position then is fine.
          .id(Theme.shared.usesLiquidGlass)
      }
      .toolbar(removing: .title)
      .modifier(ZedChrome())
      // Remembered between launches, like the terminal.
      .onChange(of: columns) { UserDefaults.standard.set(columns == .detailOnly, forKey: "sidebarHidden") }
      .modifier(MinimalChrome(session: session, columns: $columns))
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
        .font(.app(.largeTitle))
      Text("Every change, at a glance.")
        .foregroundStyle(.secondary)
      Button(AppCommand.openRepository.title, action: open)
        .keyboardShortcut(.defaultAction)
        .controlSize(.large)
        .padding(.top, 8)
      Text("Pick the folder that contains .git. You only have to do this once.")
        .font(.app(.callout))
        .foregroundStyle(.secondary)
      if let message {
        Text(message)
          .font(.app(.callout))
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
/// and your scroll position stays put. Maximized, the terminal takes the
/// diff's space and the diff collapses to nothing but stays in the tree.
private struct DiffAndTerminal: View {
  let session: RepositorySession
  @AppStorage("terminalHeight") private var terminalHeight = 240.0
  @State private var dragStart: Double?

  var body: some View {
    let maximized = session.isTerminalShown && session.isTerminalMaximized
    GeometryReader { geometry in
      VStack(spacing: 0) {
        DiffPane(session: session)
          .frame(maxWidth: .infinity, maxHeight: maximized ? 0 : .infinity)
          .clipped()
          .opacity(maximized ? 0 : 1)
          .allowsHitTesting(!maximized)
          .accessibilityHidden(maximized)
        if session.isTerminalShown, let folder = session.repositoryURL {
          if !maximized { divider(in: geometry.size.height) }
          TerminalPanel(
            folder: folder, store: session.terminals, isMaximized: maximized,
            toggleMaximized: session.toggleTerminalMaximized, split: session.splitTerminal
          ) { session.isTerminalShown = false }
          .frame(height: maximized ? geometry.size.height : clamped(terminalHeight, in: geometry.size.height))
        }
      }
    }
  }

  /// Drag to resize. The height is remembered between launches.
  private func divider(in total: Double) -> some View {
    Hairline()
      .padding(.vertical, 3)
      .contentShape(Rectangle())
      .padding(.vertical, -3)
      // Holds through a drag, unlike a pushed cursor.
      .pointerStyle(.rowResize)
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
/// the controls sit beside the switcher. With Liquid Glass off in Settings,
/// the items lose their glass capsules and sit flat on the toolbar.
private struct DiffToolbar: ViewModifier {
  @Bindable var session: RepositorySession
  @Binding var columns: NavigationSplitViewVisibility

  // Minimal empties the toolbar rather than dropping the modifier, so
  // switching Interface doesn't rebuild the window and lose your place.
  func body(content: Content) -> some View {
    let minimal = Theme.shared.isMinimal
    if #available(macOS 26, *) {
      let glass: Visibility = Theme.shared.usesLiquidGlass ? .automatic : .hidden
      content.toolbar {
        if !minimal {
          // The system's sidebar button is glass and can't be flattened, so
          // with glass off it's removed and this one stands in.
          if !Theme.shared.usesLiquidGlass {
            ToolbarItem(placement: .navigation) { sidebarButton }
              .sharedBackgroundVisibility(.hidden)
          }
          ToolbarItem(placement: .navigation) { ProjectTitle(session: session) }
            .sharedBackgroundVisibility(glass)
          ToolbarSpacer(.flexible)
          ToolbarItem { terminalButton }
            .sharedBackgroundVisibility(glass)
          ToolbarItem { layoutPicker }
            .sharedBackgroundVisibility(glass)
        }
      }
    } else {
      content.toolbar {
        if !minimal {
          ToolbarItem(placement: .navigation) { ProjectTitle(session: session) }
          controls
        }
      }
    }
  }

  @ToolbarContentBuilder private var controls: some ToolbarContent {
    ToolbarItem { terminalButton }
    ToolbarItem { layoutPicker }
  }

  private var terminalButton: some View {
    TerminalToggle(session: session)
  }

  private var sidebarButton: some View {
    Button {
      withAnimation(Motion.reveal) { columns = columns == .detailOnly ? .all : .detailOnly }
    } label: {
      Label("Sidebar", systemImage: "sidebar.left")
    }
    .buttonStyle(.borderless)
    .help(columns == .detailOnly ? "Show the sidebar" : "Hide the sidebar")
  }

  /// One icon that flips unified and split, beside the terminal's.
  private var layoutPicker: some View {
    LayoutToggle(session: session)
  }
}

/// Style Zed: the title bar in Zed's colour, solid rather than glass.
private struct ZedChrome: ViewModifier {
  func body(content: Content) -> some View {
    if let bar = Theme.shared.titleBarBackground {
      content
        .toolbarBackground(Color(nsColor: bar), for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
    } else {
      content
    }
  }
}

/// Minimal empties the toolbar, keeping only the window buttons (hiding it
/// outright takes those too), and puts one status line along the bottom of
/// the window, across both columns.
private struct MinimalChrome: ViewModifier {
  let session: RepositorySession
  @Binding var columns: NavigationSplitViewVisibility

  // Always inset, with the status line inside, so switching Interface
  // doesn't rebuild the window.
  func body(content: Content) -> some View {
    content
      .safeAreaInset(edge: .bottom, spacing: 0) {
        if Theme.shared.isMinimal {
          VStack(spacing: 0) {
            Hairline()
            StatusLine(session: session, columns: $columns)
          }
          .background(
            Theme.shared.statusBarBackground.map { AnyShapeStyle(Color(nsColor: $0)) } ?? AnyShapeStyle(.bar))
        }
      }
  }
}

/// With Liquid Glass off, removes the system's glass sidebar button;
/// `DiffToolbar` adds a flat one.
private struct FlatSidebarToggle: ViewModifier {
  func body(content: Content) -> some View {
    if !Theme.shared.isFlat {
      content
    } else {
      content.toolbar(removing: .sidebarToggle)
    }
  }
}

/// Shown only if opening takes longer than 300 ms, so a quick open never
/// flashes it.
private struct OpeningView: View {
  let name: String?
  @State private var isShown = false

  var body: some View {
    VStack(spacing: 12) {
      ProgressView().controlSize(.small)
      Text(name.map { "Opening \($0)…" } ?? "Opening…")
        .foregroundStyle(.secondary)
    }
    .opacity(isShown ? 1 : 0)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .task {
      try? await Task.sleep(for: .milliseconds(300))
      isShown = true
    }
  }
}
