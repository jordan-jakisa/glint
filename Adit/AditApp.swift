import SwiftUI

@main
struct AditApp: App {
  var body: some Scene {
    WindowGroup {
      ContentView()
    }
    .windowToolbarStyle(.unified(showsTitle: false))
    .defaultSize(width: 1100, height: 720)
    .commands {
      CommandGroup(replacing: .newItem) {}
    }
  }
}
