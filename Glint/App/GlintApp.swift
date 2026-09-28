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
      TabView {
        GeneralSettingsView()
          .tabItem { Label("General", systemImage: "gearshape") }
        AppearanceSettingsView()
          .tabItem { Label("Appearance", systemImage: "paintbrush") }
        AISettingsView()
          .tabItem { Label("AI", systemImage: "sparkles") }
        ShortcutsSettingsView()
          .tabItem { Label("Shortcuts", systemImage: "keyboard") }
      }
      .font(.app(.body))
      .tint(.themeAccent)
      .themedTextLevels()
    }
  }
}
