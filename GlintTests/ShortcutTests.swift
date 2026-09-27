import Foundation
import Testing

@testable import Glint

@MainActor
@Suite struct ShortcutTests {
  private func freshStore() -> ShortcutStore {
    let suite = "glint-shortcut-tests-\(UUID().uuidString)"
    return ShortcutStore(defaults: UserDefaults(suiteName: suite)!)
  }

  @Test func defaultsHaveNoConflicts() {
    let store = freshStore()
    let all = AppCommand.allCases.compactMap { store.shortcut(for: $0) }
    #expect(Set(all).count == all.count)
    for command in AppCommand.allCases {
      #expect(command.defaultShortcut.isSingleKey == command.isSingleKey)
    }
  }

  @Test func rebindsAndRefusesConflictsAndWrongKinds() {
    let store = freshStore()
    #expect(store.set(Shortcut("y", command: true), for: .reload) == nil)
    #expect(store.shortcut(for: .reload) == Shortcut("y", command: true))

    // Taken, a single key on a menu command, a modifier on a single key,
    // and ⌘1 to ⌘9 are all refused and leave the old key in place.
    #expect(store.set(Shortcut("b", command: true), for: .reload) == .takenBy(.switchBranch))
    #expect(store.set(Shortcut("x"), for: .reload) == .needsModifier)
    #expect(store.set(Shortcut("x", command: true), for: .nextItem) == .mustBeSingleKey)
    #expect(store.set(Shortcut("2", command: true), for: .reload) == .takenBy(.switchRepository))
    #expect(store.shortcut(for: .reload) == Shortcut("y", command: true))
  }

  @Test func singleKeysFollowTheSettings() {
    let store = freshStore()
    #expect(store.singleKeyCommand(for: "j") == .nextItem)
    #expect(store.singleKeyCommand(for: " ") == .toggleStaged)
    store.set(Shortcut("h"), for: .nextItem)
    #expect(store.singleKeyCommand(for: "j") == nil)
    #expect(store.singleKeyCommand(for: "h") == .nextItem)
    store.set(nil, for: .nextHunk)
    #expect(store.singleKeyCommand(for: "n") == nil)
    store.resetAll()
    #expect(store.singleKeyCommand(for: "j") == .nextItem)
    #expect(store.singleKeyCommand(for: "n") == .nextHunk)
  }

  @Test func displaysLikeMacMenus() {
    #expect(Shortcut("p", command: true, option: true, shift: true).display == "\u{2325}\u{21E7}\u{2318}P")
    #expect(Shortcut("return", command: true).display == "\u{2318}\u{21A9}")
    #expect(Shortcut("space").display == "Space")
  }
}
