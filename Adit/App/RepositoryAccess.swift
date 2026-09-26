import AppKit

/// Remembers the last repository so Adit reopens it on launch. Stored as a
/// bookmark rather than a path, so it follows the folder if it's moved or
/// renamed.
@MainActor
final class RepositoryAccess {
  private static let bookmarkKey = "lastRepositoryBookmark"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The last repository, if its bookmark still resolves. One that doesn't
  /// (folder deleted, drive unplugged) is forgotten rather than retried on
  /// every launch.
  func restore() -> URL? {
    guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil,
        bookmarkDataIsStale: &isStale)
    else {
      forget()
      return nil
    }
    if isStale { adopt(url) }
    return url
  }

  /// Shows an open panel for a folder. Returns nil if the user cancels.
  func choose() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    panel.message = "Pick a git repository, or any folder inside one."
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url
  }

  /// Saves `url` as the repository to reopen next launch.
  func adopt(_ url: URL) {
    guard let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return }
    defaults.set(data, forKey: Self.bookmarkKey)
  }

  func forget() {
    defaults.removeObject(forKey: Self.bookmarkKey)
  }
}
