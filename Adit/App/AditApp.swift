import SwiftUI

@main
struct AditApp: App {
  init() {
    RepositorySession.prewarm()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
    }
    .windowToolbarStyle(.unified)
    .defaultSize(width: 1100, height: 720)
    .commands {
      AditCommands()
    }

    Settings {
      TabView {
        GeneralSettingsView()
          .tabItem { Label("General", systemImage: "gearshape") }
        AISettingsView()
          .tabItem { Label("AI", systemImage: "sparkles") }
      }
    }
  }
}
