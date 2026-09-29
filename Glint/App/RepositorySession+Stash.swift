import Foundation

/// Stashes, like Zed's: make one (all changes, tracked, or staged), list
/// them, and apply, pop, or drop one. All through system git, so hooks and
/// config apply like in the terminal.
extension RepositorySession {
  /// The stash sheet on screen.
  enum StashSheet: Identifiable, Hashable {
    /// Asking for an optional name before making a stash.
    case name(StashKind)
    /// Browsing stashes.
    case picker

    var id: String {
      switch self {
      case .name(let kind): "name-\(kind.rawValue)"
      case .picker: "picker"
      }
    }
  }

  /// The stash list sheet. Showing it reloads the list.
  var isStashPickerShown: Bool {
    get { stashSheet == .picker }
    set {
      if newValue {
        stashSheet = .picker
        loadStashes()
      } else if stashSheet == .picker {
        stashSheet = nil
      }
    }
  }

  func loadStashes() {
    guard let repository else { return }
    let git = SystemGit(directory: repository.url)
    Task {
      // A repository git can't list stashes for simply has none to show.
      stashes = Stash.parse(list: (try? await git.run(["stash", "list", "--format=\(Stash.listFormat)"])) ?? "")
    }
  }

  // MARK: Making a stash

  /// Asks for a name, then makes the stash. For menus and keys.
  func requestStash(_ kind: StashKind) {
    guard repository != nil else { return }
    stashSheet = .name(kind)
  }

  func stashAll(named name: String = "") { stash(.all, named: name) }
  func stashTracked(named name: String = "") { stash(.tracked, named: name) }
  func stashStaged(named name: String = "") { stash(.staged, named: name) }

  func stash(_ kind: StashKind, named name: String) {
    guard let repository, !isStashing else { return }
    stashSheet = nil
    Timing.writes.notice("stash push \(kind.rawValue, privacy: .public)")
    let git = SystemGit(directory: repository.url)
    isStashing = true
    Task {
      defer { isStashing = false }
      do {
        let output = try await git.run(kind.pushArguments(named: name))
        // Git exits 0 when there's nothing to stash.
        if output.contains("No local changes to save") {
          alert = UserAlert("Nothing to stash", message: Self.nothingToStash(kind))
        }
      } catch {
        alert = UserAlert("Couldn't stash your changes", error: error)
      }
      afterStashChange()
    }
  }

  private static func nothingToStash(_ kind: StashKind) -> String {
    switch kind {
    case .all: "You don't have any changes to stash."
    case .tracked: "You don't have changes to tracked files. To stash new files too, stash all changes."
    case .staged: "You haven't staged anything. Stage what you want to set aside, or stash all changes."
    }
  }

  // MARK: Using a stash

  func applyStash(_ stash: Stash) { use(stash, "apply") }
  func popStash(_ stash: Stash) { use(stash, "pop") }
  func dropStash(_ stash: Stash) { use(stash, "drop") }

  /// Applies the newest stash and keeps it.
  func applyLatestStash() { use(nil, "apply") }
  /// Applies the newest stash and drops it.
  func popLatestStash() { use(nil, "pop") }

  /// The unified diff a stash holds, untracked files included, for the
  /// picker's preview. Very long ones are cut to `lineLimit` lines.
  func stashDiff(_ stash: Stash, lineLimit: Int = 5_000) async throws -> (text: String, isTruncated: Bool) {
    guard let repository else { return ("", false) }
    let git = SystemGit(directory: repository.url)
    let base = ["stash", "show", "--patch", "--no-color", "--no-ext-diff"]
    let text: String
    do {
      text = try await git.run(base + ["--include-untracked", stash.id])
    } catch let failure as SystemGit.Failure where failure.message.contains("include-untracked") {
      // Before git 2.38 there's no --include-untracked here: show the rest.
      text = try await git.run(base + [stash.id])
    }
    var lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    if lines.last?.isEmpty == true { lines.removeLast() }
    guard lines.count > lineLimit else { return (lines.joined(separator: "\n"), false) }
    return (lines.prefix(lineLimit).joined(separator: "\n"), true)
  }

  /// Runs `git stash <verb>` on `stash`, or on the newest one when nil.
  /// Stashes shift as others are made or dropped (from the terminal too),
  /// so one picked from the list is found again by its commit id first.
  private func use(_ stash: Stash?, _ verb: String) {
    guard let repository, !isStashing else { return }
    // Apply and pop close the picker: you go back to your changes. Drop
    // keeps it open to drop another.
    if verb != "drop", stashSheet == .picker { stashSheet = nil }
    Timing.writes.notice("stash \(verb, privacy: .public)")
    let git = SystemGit(directory: repository.url)
    isStashing = true
    Task {
      defer { isStashing = false }
      do {
        var reference = "stash@{0}"
        if let stash {
          let current = Stash.parse(list: try await git.run(["stash", "list", "--format=\(Stash.listFormat)"]))
          guard let found = current.first(where: { $0.id == stash.id }) else {
            stashSheet = nil
            alert = UserAlert(
              "That stash is gone",
              message: "It was popped or dropped somewhere else, like the terminal. The list is up to date now.")
            afterStashChange()
            return
          }
          reference = found.reference
        }
        _ = try await git.run(["stash", verb, reference])
      } catch {
        stashSheet = nil
        alert = Self.stashAlert(verb, error: error)
      }
      afterStashChange()
    }
  }

  /// Git's conflict output doesn't say what to do about the stash; this does.
  private static func stashAlert(_ verb: String, error: Error) -> UserAlert {
    var alert = UserAlert("Couldn't \(verb) the stash", error: error)
    let raw = (error as? SystemGit.Failure)?.message ?? ""
    if raw.contains("CONFLICT") {
      alert.title = "The stash conflicts with your changes"
      alert.message =
        verb == "pop"
        ? "Its changes are in, but some files conflict. Fix the ones marked !, then stage them. The stash is still in the list, so drop it once you're done."
        : "Its changes are in, but some files conflict. Fix the ones marked !, then stage them."
      alert.details = raw
    }
    return alert
  }

  private func afterStashChange() {
    loadStashes()
    refresh()
  }
}
