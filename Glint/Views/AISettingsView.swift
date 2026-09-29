import SwiftUI

/// Settings, AI tab: pick a provider and one of its free models.
struct AISettingsView: View {
  @Bindable private var settings = AISettings.shared
  @State private var keyDraft = ""
  @State private var keySaved = false
  @State private var keyFailed = false

  var body: some View {
    SettingsPage(title: "AI") {
      SettingsSection(title: "Commit messages")
      SettingsRow(
        title: "Write commit messages with AI",
        description: "Sends your diff to the provider only when you press \u{2728}."
      ) {
        Toggle("Write commit messages with AI", isOn: $settings.isEnabled).labelsHidden().toggleStyle(.switch)
      }

      SettingsSection(title: "Provider")
      SettingsRow(title: "Provider", description: settings.provider.privacyNote) {
        Picker("Provider", selection: $settings.provider) {
          ForEach(AIProvider.allCases) { Text($0.name).tag($0) }
        }
        .labelsHidden()
        .fixedSize()
      }
      SettingsRow(title: "API key", description: keyStatus) {
        HStack(spacing: 6) {
          SecureField(settings.hasKey ? "Paste to replace" : "Paste your key", text: $keyDraft)
            .onSubmit(saveKey)
            .frame(width: 150)
          Button(keySaved ? "Saved" : "Save", action: saveKey)
            .disabled(keyDraft.isEmpty)
            .fixedSize()
          Link("Get a Key", destination: settings.provider.keyURL)
            .fixedSize()
        }
      }
      SettingsRow(title: "Free model", description: settings.modelsError ?? "Free models from \(settings.provider.name).") {
        HStack(spacing: 4) {
          Picker("Model", selection: Binding(get: { settings.modelID }, set: { settings.modelID = $0 })) {
            if settings.models.isEmpty {
              Text(settings.isLoadingModels ? "Loading\u{2026}" : "No free models right now").tag(String?.none)
            }
            ForEach(settings.models) { Text($0.name).tag(Optional($0.id)) }
          }
          .labelsHidden()
          .frame(width: 200)
          Button {
            settings.loadModels()
          } label: {
            Image(systemName: "arrow.clockwise").hitTarget()
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Reload the free models")
          .help("Reload the free models")
        }
      }

      SettingsSection(title: "How to write them")
      SettingsRow(
        title: "Follow the repository's rules", description: "Reads AGENTS.md or CLAUDE.md when there is one.",
        isModified: !settings.followsRepositoryRules, reset: { settings.followsRepositoryRules = true }
      ) {
        Toggle("Follow the repository's rules", isOn: $settings.followsRepositoryRules)
          .labelsHidden()
          .toggleStyle(.switch)
      }
      SettingsRow(
        title: "Your instructions", description: "Like \u{201C}use conventional commits\u{201D}.",
        isModified: !settings.instructions.isEmpty, reset: { settings.instructions = "" }
      ) {
        TextField("Instructions", text: $settings.instructions, axis: .vertical)
          .labelsHidden()
          .lineLimit(1...4)
          .frame(width: 260)
      }
    }
    .onAppear {
      settings.refreshKeyState()
      if settings.models.isEmpty { settings.loadModels() }
    }
    .onChange(of: settings.provider) {
      keyDraft = ""
      keySaved = false
      keyFailed = false
    }
  }

  private var keyStatus: String {
    if keyFailed { return "Couldn't save your key to the Keychain. Unlock your login keychain, then save again." }
    if settings.hasKey { return "Saved in your Keychain; it stays there between launches." }
    return "No key saved. Free models still need one."
  }

  private func saveKey() {
    guard !keyDraft.isEmpty else { return }
    // On failure the draft stays, so you can save again without retyping.
    keyFailed = !settings.saveKey(keyDraft)
    guard !keyFailed else { return }
    keyDraft = ""
    keySaved = true
  }
}
