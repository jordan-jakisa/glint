import AppKit

/// Sandbox access to the repository folder the user picked, kept across
/// launches with a security-scoped bookmark. Users never see the bookmark: they
/// pick a folder once and Adit reopens it next time.
@MainActor
final class RepositoryAccess {
  private static let bookmarkKey = "lastRepositoryBookmark"
  private let defaults: UserDefaults
  private var accessedURL: URL?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  /// The last repository, if its bookmark still resolves. A bookmark that no
  /// longer resolves (folder deleted, drive unplugged) is forgotten rather than
  /// retried on every launch.
  func restore() -> URL? {
    guard let data = defaults.data(forKey: Self.bookmarkKey) else { return nil }
    var isStale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
        relativeTo: nil, bookmarkDataIsStale: &isStale),
      url.startAccessingSecurityScopedResource()
    else {
      forget()
      return nil
    }
    accessedURL = url
    // A stale bookmark still resolves this time but may not next time (the
    // folder moved or was renamed). Replace it while access is open.
    if isStale { remember(url) }
    return url
  }

  /// Shows an open panel for a folder. Returns nil if the user cancels.
  func choose() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    panel.message = "Pick a git repository folder."
    guard panel.runModal() == .OK, let url = panel.url else { return nil }
    return url
  }

  /// Makes `url` the current repository: holds its access open for this
  /// session and saves it for the next launch.
  func adopt(_ url: URL) {
    if accessedURL != url {
      release()
      // Access from an open panel is already granted for this launch; starting
      // it anyway keeps the start/stop calls balanced for both paths.
      if url.startAccessingSecurityScopedResource() { accessedURL = url }
    }
    remember(url)
  }

  /// Drops the saved repository and any access held for it.
  func forget() {
    release()
    defaults.removeObject(forKey: Self.bookmarkKey)
  }

  private func remember(_ url: URL) {
    guard
      let data = try? url.bookmarkData(
        options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return }
    defaults.set(data, forKey: Self.bookmarkKey)
  }

  private func release() {
    accessedURL?.stopAccessingSecurityScopedResource()
    accessedURL = nil
  }
}
