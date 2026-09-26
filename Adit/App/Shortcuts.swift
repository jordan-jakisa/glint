import AppKit
import Observation
import SwiftUI

/// A key plus modifiers, as stored in settings and shown in menus.
struct Shortcut: Codable, Hashable, Sendable {
  /// One character (`j`, `\`, `` ` ``), or a named key: return, up, down,
  /// left, right, space, tab, escape, delete.
  var key: String
  var command = false
  var option = false
  var control = false
  var shift = false

  /// Single keys have no ⌘, ⌥, or ⌃. Adit handles those itself, only while
  /// you aren't typing, instead of as menu shortcuts.
  var isSingleKey: Bool { !command && !option && !control }

  var display: String {
    (control ? "\u{2303}" : "") + (option ? "\u{2325}" : "") + (shift ? "\u{21E7}" : "")
      + (command ? "\u{2318}" : "") + keyDisplay
  }

  private var keyDisplay: String {
    switch key {
    case "return": "\u{21A9}"
    case "up": "\u{2191}"
    case "down": "\u{2193}"
    case "left": "\u{2190}"
    case "right": "\u{2192}"
    case "space": "Space"
    case "tab": "\u{21E5}"
    case "escape": "\u{238B}"
    case "delete": "\u{232B}"
    default: key.uppercased()
    }
  }

  var keyEquivalent: KeyEquivalent {
    switch key {
    case "return": .return
    case "up": .upArrow
    case "down": .downArrow
    case "left": .leftArrow
    case "right": .rightArrow
    case "space": .space
    case "tab": .tab
    case "escape": .escape
    case "delete": .delete
    default: KeyEquivalent(Character(key))
    }
  }

  var keyboardShortcut: KeyboardShortcut {
    var modifiers: EventModifiers = []
    if command { modifiers.insert(.command) }
    if option { modifiers.insert(.option) }
    if control { modifiers.insert(.control) }
    if shift { modifiers.insert(.shift) }
    return KeyboardShortcut(keyEquivalent, modifiers: modifiers)
  }

  /// The shortcut a key press would record, or nil for keys that can't be
  /// one (modifiers alone).
  init?(event: NSEvent) {
    let flags = event.modifierFlags
    command = flags.contains(.command)
    option = flags.contains(.option)
    control = flags.contains(.control)
    shift = flags.contains(.shift)
    switch event.keyCode {
    case 36, 76: key = "return"
    case 126: key = "up"
    case 125: key = "down"
    case 123: key = "left"
    case 124: key = "right"
    case 49: key = "space"
    case 48: key = "tab"
    case 53: key = "escape"
    case 51: key = "delete"
    default:
      guard let character = event.charactersIgnoringModifiers?.lowercased().first,
        !character.isWhitespace
      else { return nil }
      key = String(character)
    }
  }

  init(_ key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
    self.key = key
    self.command = command
    self.option = option
    self.control = control
    self.shift = shift
  }

  /// Whether a plain key press (no ⌘, ⌥, ⌃) is this single-key shortcut.
  func matches(_ character: Character) -> Bool {
    guard isSingleKey, !shift else { return false }
    return character == " " ? key == "space" : key == String(character).lowercased()
  }
}

/// Every command that can have a key.
enum AppCommand: String, CaseIterable, Identifiable, Sendable {
  case openRepository, reload, toggleLayout, showTerminal, openExternalTerminal
  case switchRepository, switchBranch, writeMessage, commit
  case fetch, pull, push
  case nextFile, previousFile, stageAll, unstageAll
  case nextItem, previousItem, nextHunk, previousHunk, toggleCollapsed, toggleStaged, stagePartial,
    focusCommitMessage

  var id: String { rawValue }

  var title: String {
    switch self {
    case .openRepository: "Open repository"
    case .reload: "Reload"
    case .toggleLayout: "Unified or split"
    case .showTerminal: "Show or hide the terminal"
    case .openExternalTerminal: "Open in your terminal app"
    case .switchRepository: "Switch repository"
    case .switchBranch: "Switch branch"
    case .writeMessage: "Write commit message with AI"
    case .commit: "Commit"
    case .fetch: "Fetch"
    case .pull: "Pull"
    case .push: "Push"
    case .nextFile: "Next file in the diff"
    case .previousFile: "Previous file in the diff"
    case .stageAll: "Stage all"
    case .unstageAll: "Unstage all"
    case .nextItem: "Next file or commit"
    case .previousItem: "Previous file or commit"
    case .nextHunk: "Next hunk"
    case .previousHunk: "Previous hunk"
    case .toggleCollapsed: "Collapse or expand the file"
    case .toggleStaged: "Stage or unstage the selected file"
    case .stagePartial: "Stage or unstage lines or hunk"
    case .focusCommitMessage: "Write the commit message"
    }
  }

  /// Single-key commands run only while you aren't typing, so their keys
  /// must have no ⌘, ⌥, or ⌃; menu commands must have one.
  var isSingleKey: Bool {
    switch self {
    case .nextItem, .previousItem, .nextHunk, .previousHunk, .toggleCollapsed, .toggleStaged,
      .stagePartial, .focusCommitMessage:
      true
    default: false
    }
  }

  var defaultShortcut: Shortcut {
    switch self {
    case .openRepository: Shortcut("o", command: true)
    case .reload: Shortcut("r", command: true)
    case .toggleLayout: Shortcut("\\", command: true)
    case .showTerminal: Shortcut("t", command: true)
    case .openExternalTerminal: Shortcut("t", command: true, option: true)
    case .switchRepository: Shortcut("r", command: true, shift: true)
    case .switchBranch: Shortcut("b", command: true)
    case .writeMessage: Shortcut("g", command: true, option: true)
    case .commit: Shortcut("return", command: true)
    case .fetch: Shortcut("f", command: true, option: true)
    case .pull: Shortcut("p", command: true, option: true)
    case .push: Shortcut("p", command: true, option: true, shift: true)
    case .nextFile: Shortcut("down", command: true)
    case .previousFile: Shortcut("up", command: true)
    case .stageAll: Shortcut("s", command: true, option: true)
    case .unstageAll: Shortcut("u", command: true, option: true)
    case .nextItem: Shortcut("j")
    case .previousItem: Shortcut("k")
    case .nextHunk: Shortcut("n")
    case .previousHunk: Shortcut("p")
    case .toggleCollapsed: Shortcut("o")
    case .toggleStaged: Shortcut("space")
    case .stagePartial: Shortcut("s")
    case .focusCommitMessage: Shortcut("c")
    }
  }
}

/// Your keys, where they differ from the defaults. ⌘1 to ⌘9 for
/// repositories are fixed.
@MainActor
@Observable
final class ShortcutStore {
  static let shared = ShortcutStore()

  /// Commands whose key you changed, and commands you left without one.
  private(set) var custom: [String: Shortcut] = [:]
  private(set) var cleared: Set<String> = []

  private let defaults: UserDefaults
  private static let customKey = "shortcuts"
  private static let clearedKey = "shortcutsCleared"

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    if let data = defaults.data(forKey: Self.customKey),
      let decoded = try? JSONDecoder().decode([String: Shortcut].self, from: data)
    {
      custom = decoded
    }
    cleared = Set(defaults.stringArray(forKey: Self.clearedKey) ?? [])
  }

  func shortcut(for command: AppCommand) -> Shortcut? {
    if cleared.contains(command.rawValue) { return nil }
    return custom[command.rawValue] ?? command.defaultShortcut
  }

  enum Problem: Equatable {
    case needsModifier
    case mustBeSingleKey
    case takenBy(AppCommand)
  }

  /// Why `shortcut` can't be `command`'s key, or nil if it can.
  func problem(with shortcut: Shortcut, for command: AppCommand) -> Problem? {
    if command.isSingleKey, !shortcut.isSingleKey { return .mustBeSingleKey }
    if !command.isSingleKey, shortcut.isSingleKey { return .needsModifier }
    // ⌘1 to ⌘9 belong to the repositories.
    if shortcut.command, !shortcut.option, !shortcut.control, !shortcut.shift,
      let digit = Int(shortcut.key), (1...9).contains(digit)
    {
      return .takenBy(.switchRepository)
    }
    let owner = AppCommand.allCases.first { $0 != command && self.shortcut(for: $0) == shortcut }
    return owner.map(Problem.takenBy)
  }

  /// Saves a key, or clears it with nil. Refuses a key another command has.
  @discardableResult
  func set(_ shortcut: Shortcut?, for command: AppCommand) -> Problem? {
    guard let shortcut else {
      custom[command.rawValue] = nil
      cleared.insert(command.rawValue)
      save()
      return nil
    }
    if let problem = problem(with: shortcut, for: command) { return problem }
    cleared.remove(command.rawValue)
    custom[command.rawValue] = shortcut == command.defaultShortcut ? nil : shortcut
    save()
    return nil
  }

  func resetAll() {
    custom = [:]
    cleared = []
    save()
  }

  /// The single-key command a plain key press runs, if any.
  func singleKeyCommand(for character: Character) -> AppCommand? {
    AppCommand.allCases.first { $0.isSingleKey && shortcut(for: $0)?.matches(character) == true }
  }

  private func save() {
    defaults.set(try? JSONEncoder().encode(custom), forKey: Self.customKey)
    defaults.set(Array(cleared), forKey: Self.clearedKey)
  }
}

extension View {
  /// The key you've set for `command`, if any.
  func shortcut(_ command: AppCommand) -> some View {
    keyboardShortcut(ShortcutStore.shared.shortcut(for: command)?.keyboardShortcut)
  }
}
