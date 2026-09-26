import SwiftUI

struct RootView: View {
  @State private var session = RepositorySession()

  var body: some View {
    content
      .navigationTitle(session.info?.name ?? "Adit")
      .navigationSubtitle(subtitle)
      .focusedSceneValue(\.session, session)
      .onAppear { session.restoreLastRepository() }
      .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
        session.refresh()
      }
      .alert(
        "Couldn't open that folder",
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
        DiffPane(session: session)
      }
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Picker("Layout", selection: $session.layout) {
            Text("Unified").tag(DiffLayout.unified)
            Text("Split").tag(DiffLayout.split)
          }
          .pickerStyle(.segmented)
          .help("Switch between unified and split diffs (⌘\\)")
        }
      }
    }
  }

  private var subtitle: String {
    guard let info = session.info else { return "" }
    return info.branch ?? "detached HEAD"
  }
}

private struct WelcomeView: View {
  let message: String?
  let open: () -> Void

  var body: some View {
    VStack(spacing: 14) {
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
