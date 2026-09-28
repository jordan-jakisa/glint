import SwiftUI

/// Settings, AI tab: pick a provider and one of its free models.
struct AISettingsView: View {
  @Bindable private var settings = AISettings.shared
  @State private var keyDraft = ""
  @State private var keySaved = false
  @State private var keyFailed = false

  var body: some View {
    Form {
      Section("Commit messages") {
        Toggle("Write commit messages with AI", isOn: $settings.isEnabled)
        Text("Sends your diff to the provider only when you press \u{2728}.")
          .font(.app(.callout))
          .foregroundStyle(.secondary)
      }

      Section("Provider") {
        Picker("Provider", selection: $settings.provider) {
          ForEach(AIProvider.allCases) { Text($0.name).tag($0) }
        }
        HStack {
          SecureField("API key", text: $keyDraft)
            .onSubmit(saveKey)
          Button(keySaved ? "Saved" : "Save", action: saveKey)
            .disabled(keyDraft.isEmpty)
        }
        HStack {
          Text(keyStatus)
            .foregroundStyle(keyFailed ? .red : .secondary)
          Spacer()
          Link("Get a Key", destination: settings.provider.keyURL)
        }
        .font(.app(.callout))
      }

      Section("Free model") {
        HStack {
          Picker("Model", selection: Binding(get: { settings.modelID }, set: { settings.modelID = $0 })) {
            if settings.models.isEmpty {
              Text(settings.isLoadingModels ? "Loading…" : "No free models right now").tag(String?.none)
            }
            ForEach(settings.models) { Text($0.name).tag(Optional($0.id)) }
          }
          Button {
            settings.loadModels()
          } label: {
            Image(systemName: "arrow.clockwise")
          }
          .buttonStyle(.borderless)
          .help("Reload the free models")
        }
        if let error = settings.modelsError {
          Text(error).font(.app(.callout)).foregroundStyle(.red)
        }
        Text(settings.provider.privacyNote)
          .font(.app(.callout))
          .foregroundStyle(.secondary)
      }

      Section("How to write them") {
        Toggle("Follow the repository's AGENTS.md or CLAUDE.md", isOn: $settings.followsRepositoryRules)
        TextField(
          "Your own instructions, like \u{201C}use conventional commits\u{201D}", text: $settings.instructions,
          axis: .vertical
        )
        .lineLimit(3...6)
      }
    }
    .formStyle(.grouped)
    .frame(height: 560)
    .onAppear {
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
    if settings.hasKey { return "Key saved in your Keychain." }
    if settings.keyUnchecked { return "Glint checks for a saved key the first time you write a message." }
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
