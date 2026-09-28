import SwiftUI

@main
struct GlintApp: App {
  init() {
    AppFont.register()
    Theme.shared.apply()
    LegacyMigration.run()
    RepositorySession.prewarm()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .font(.app(.body))
        .tint(.themeAccent)
        .themedTextLevels()
    }
    .windowToolbarStyle(.unified)
    .defaultSize(width: 1100, height: 720)
    .commands {
      // Hide and show the sidebar from the View menu and ⌃⌘S, in every
      // interface, including Minimal, which has no toolbar button.
      SidebarCommands()
      GlintCommands()
    }

    Settings {
      SettingsView()
      .font(.app(.body))
      .tint(.themeAccent)
      .themedTextLevels()
    }
    // The window fits each tab rather than keeping one fixed height.
    .windowResizability(.contentSize)
  }
}
