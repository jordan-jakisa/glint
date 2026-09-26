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
    Form {
      Section("Menu shortcuts") {
        ForEach(AppCommand.allCases.filter { !$0.isSingleKey }) { row($0) }
      }
      Section {
        ForEach(AppCommand.allCases.filter(\.isSingleKey)) { row($0) }
      } header: {
        Text("Single keys")
      } footer: {
        Text("These work while you aren't typing, and never in the commit message or terminal. \u{2318}1 to \u{2318}9 always switch repository.")
          .foregroundStyle(.secondary)
      }
      Section {
        HStack {
          if let message {
            Text(message).foregroundStyle(.red)
          }
          Spacer()
          Button("Reset to Defaults") {
            store.resetAll()
            message = nil
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 520, height: 560)
    .onDisappear(perform: stopRecording)
  }

  private func row(_ command: AppCommand) -> some View {
    HStack {
      Text(command.title)
      Spacer()
      Button {
        recording == command ? stopRecording() : startRecording(command)
      } label: {
        Text(label(for: command))
          .font(.body.monospaced())
          .frame(minWidth: 90)
      }
      .buttonStyle(.bordered)
      .tint(recording == command ? .accentColor : nil)
      Button {
        store.set(nil, for: command)
      } label: {
        Image(systemName: "xmark.circle.fill")
      }
      .buttonStyle(.borderless)
      .foregroundStyle(.secondary)
      .help("Remove this shortcut")
      .disabled(store.shortcut(for: command) == nil)
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
