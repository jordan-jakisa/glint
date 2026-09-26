import AppKit

/// Terminal apps Adit can open a repository in. Ghostty first: when it's
/// installed, it's probably the one you use.
enum TerminalApp: String, CaseIterable, Identifiable, Sendable {
  case ghostty, iTerm, warp, terminal

  var id: String { rawValue }

  var name: String {
    switch self {
    case .ghostty: "Ghostty"
    case .iTerm: "iTerm"
    case .warp: "Warp"
    case .terminal: "Terminal"
    }
  }

  var bundleIdentifier: String {
    switch self {
    case .ghostty: "com.mitchellh.ghostty"
    case .iTerm: "com.googlecode.iterm2"
    case .warp: "dev.warp.Warp-Stable"
    case .terminal: "com.apple.Terminal"
    }
  }

  @MainActor var applicationURL: URL? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
  }

  @MainActor var isInstalled: Bool { applicationURL != nil }

  /// How to ask this app for a window at `folder`. Most open a folder handed
  /// to them; Ghostty takes the directory as an argument, in a new instance,
  /// the way its docs recommend for `open`.
  func launchRequest(at folder: URL) -> (openFolder: Bool, arguments: [String], newInstance: Bool) {
    switch self {
    case .ghostty: (false, ["--working-directory=\(folder.path)"], true)
    case .iTerm, .warp, .terminal: (true, [], false)
    }
  }

  private static let key = "terminalApp"

  /// The one picked in Settings, else the first installed.
  @MainActor static var preferred: TerminalApp {
    get {
      if let saved = UserDefaults.standard.string(forKey: key).flatMap(TerminalApp.init(rawValue:)),
        saved.isInstalled
      {
        return saved
      }
      return allCases.first(where: \.isInstalled) ?? .terminal
    }
    set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
  }

  /// Opens a window of this app at `folder`.
  @MainActor func open(at folder: URL) async throws {
    guard let app = applicationURL else {
      throw TerminalError(message: "\(name) isn't installed. Pick another terminal in Settings (⌘,).")
    }
    let request = launchRequest(at: folder)
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = request.arguments
    configuration.createsNewApplicationInstance = request.newInstance
    configuration.activates = true
    if request.openFolder {
      _ = try await NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: configuration)
    } else {
      _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
    }
  }
}

struct TerminalError: Error, CustomStringConvertible {
  let message: String
  var description: String { message }
}
