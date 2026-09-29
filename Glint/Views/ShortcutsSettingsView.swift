import AppKit
import SwiftUI

/// Settings, Shortcuts tab: every command and its key. Click a key to record
/// a new one.
struct ShortcutsSettingsView: View {
  private let store = ShortcutStore.shared
  @State private var recording: AppCommand?
  @State private var message: String?
  @State private var monitor: Any?

  var body: some View {
    SettingsPage(title: "Keymap") {
      if let message {
        Text(message)
          .foregroundStyle(.red)
          .padding(.horizontal, 32)
          .padding(.top, 8)
      }
      SettingsSection(title: "Menu shortcuts")
      ForEach(AppCommand.allCases.filter { !$0.isSingleKey }) { row($0) }
      SettingsSection(title: "Single keys, while you're not typing")
      ForEach(AppCommand.allCases.filter(\.isSingleKey)) { row($0) }
      SettingsRow(title: "Reset every shortcut", description: "\u{2318}1 to \u{2318}9 always switch repository.") {
        Button("Reset All") {
          store.resetAll()
          message = nil
        }
      }
    }
    .onDisappear(perform: stopRecording)
  }

  private func row(_ command: AppCommand) -> some View {
    SettingsRow(
      title: command.title, description: "",
      isModified: store.shortcut(for: command) != command.defaultShortcut,
      reset: { _ = store.set(command.defaultShortcut, for: command) }
    ) {
      HStack(spacing: 6) {
        Button {
          recording == command ? stopRecording() : startRecording(command)
        } label: {
          Text(label(for: command))
            .font(.code(.body))
            .frame(minWidth: 90)
        }
        .buttonStyle(.bordered)
        .tint(recording == command ? Color.themeAccent : nil)
        Button {
          store.set(nil, for: command)
        } label: {
          Image(systemName: "xmark.circle.fill").hitTarget()
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .accessibilityLabel("Remove the shortcut for \(command.title)")
        .help("Remove this shortcut")
        .disabled(store.shortcut(for: command) == nil)
      }
    }
  }

  private func label(for command: AppCommand) -> String {
    if recording == command { return command.isSingleKey ? "Press a key" : "Press keys" }
    return store.shortcut(for: command)?.display ?? "None"
  }

  private func startRecording(_ command: AppCommand) {
    stopRecording()
    recording = command
    message = nil
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      let shortcut = Shortcut(event: event)
      let isEscape = event.keyCode == 53
      MainActor.assumeIsolated { record(shortcut, escape: isEscape) }
      return nil
    }
  }

  private func record(_ shortcut: Shortcut?, escape: Bool) {
    guard let command = recording else { return }
    defer { stopRecording() }
    // Escape alone cancels; a shortcut can still use it with modifiers.
    if escape, shortcut?.isSingleKey == true { return }
    guard let shortcut else { return }
    switch store.set(shortcut, for: command) {
    case .none: message = nil
    case .needsModifier: message = "Menu shortcuts need \u{2318}, \u{2325}, or \u{2303}."
    case .mustBeSingleKey: message = "Single keys can't use \u{2318}, \u{2325}, or \u{2303}."
    case .takenBy(let other): message = "\(shortcut.display) is already \u{201C}\(other.title)\u{201D}."
    }
  }

  private func stopRecording() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    recording = nil
  }
}
