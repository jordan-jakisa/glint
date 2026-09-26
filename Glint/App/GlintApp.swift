import SwiftUI

@main
struct GlintApp: App {
  init() {
    LegacyMigration.run()
    RepositorySession.prewarm()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
    .windowToolbarStyle(.unified)
    .defaultSize(width: 1100, height: 720)
    .commands {
      GlintCommands()
    }

    Settings {
      TabView {
        GeneralSettingsView()
          .tabItem { Label("General", systemImage: "gearshape") }
        AISettingsView()
          .tabItem { Label("AI", systemImage: "sparkles") }
        ShortcutsSettingsView()
          .tabItem { Label("Shortcuts", systemImage: "keyboard") }
      }
    }
  }
}
