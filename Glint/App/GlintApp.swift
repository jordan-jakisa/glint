import SwiftUI

/// Folders handed to Glint from outside (`open -a Glint <folder>`, a folder
/// dropped on the Dock icon), like `zed <folder>`. The window opens them.
final class AppDelegate: NSObject, NSApplicationDelegate {
  static let openFolders = Notification.Name("GlintOpenFolders")

  func application(_ application: NSApplication, open urls: [URL]) {
    NotificationCenter.default.post(name: Self.openFolders, object: urls)
  }
}

@main
struct GlintApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  init() {
    AppFont.register()
    Theme.shared.apply()
    LegacyMigration.run()
    RepositorySession.prewarm()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        // An opened folder goes to the window you have, not a new one.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
