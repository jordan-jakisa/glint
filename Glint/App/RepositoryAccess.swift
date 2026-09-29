import AppKit

/// Remembers the projects you open, newest first, so Glint reopens the last
/// one on launch and the title's switcher lists the rest. A project is a
/// repository or a folder of them. Stored as bookmarks rather than paths, so
/// they follow a folder that's moved or renamed.
@MainActor
final class RepositoryAccess {
  private static let recentsKey = "recentProjectBookmarks"
  /// Where v0.1 kept the one repository it reopened.
  private static let legacyKey = "lastRepositoryBookmark"
  static let recentLimit = 10
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let legacy = defaults.data(forKey: Self.legacyKey) {
      stored = [legacy] + stored
      defaults.removeObject(forKey: Self.legacyKey)
    }
  }

  /// The last project, if it still resolves.
  func restore() -> URL? {
    recents().first
  }

  /// Your projects, newest first. Ones that no longer resolve (folder
  /// deleted, drive unplugged) are forgotten rather than listed.
  func recents() -> [URL] {
    var kept: [Data] = []
    var urls: [URL] = []
    var changed = false
    for data in stored {
      var isStale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil,
          bookmarkDataIsStale: &isStale),
        FileManager.default.fileExists(atPath: url.path)
      else {
        changed = true
        continue
      }
      if isStale, let fresh = Self.bookmark(url) {
        kept.append(fresh)
        changed = true
      } else {
        kept.append(data)
      }
      urls.append(url)
    }
    if changed { stored = kept }
    return urls
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

  /// Puts `url` first: the project to reopen next launch.
  func adopt(_ url: URL) {
    guard let data = Self.bookmark(url) else { return }
    let others = zip(stored, recents()).filter { !Self.same($0.1, url) }.map(\.0)
    stored = Array(([data] + others).prefix(Self.recentLimit))
  }

  /// Forgets every project but the newest, which is the one open now and
  /// the one to reopen on launch. From Settings.
  func clearOlderRecents() {
    stored = Array(stored.prefix(1))
  }

  /// Drops `url` from the list, after it failed to open.
  func forget(_ url: URL) {
    let urls = recents()
    stored = zip(stored, urls).filter { !Self.same($0.1, url) }.map(\.0)
  }

  private var stored: [Data] {
    get { defaults.array(forKey: Self.recentsKey) as? [Data] ?? [] }
    set { defaults.set(newValue, forKey: Self.recentsKey) }
  }

  private static func bookmark(_ url: URL) -> Data? {
    try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
  }

  private static func same(_ a: URL, _ b: URL) -> Bool {
    a.standardizedFileURL.resolvingSymlinksInPath().path == b.standardizedFileURL.resolvingSymlinksInPath().path
  }
}
