import Foundation
import Observation

/// Which provider and model write commit messages. Off until you turn it on:
/// generating sends your diff to someone else's server. Keys live in the
/// Keychain; everything else here is in UserDefaults.
@MainActor
@Observable
final class AISettings {
  static let shared = AISettings()

  var isEnabled: Bool {
    didSet { defaults.set(isEnabled, forKey: "aiEnabled") }
  }
  var provider: AIProvider {
    didSet {
      defaults.set(provider.rawValue, forKey: "aiProvider")
      if provider != oldValue { loadModels() }
    }
  }
  /// The chosen model for each provider, so switching back keeps your pick.
  private(set) var modelIDs: [String: String] {
    didSet { defaults.set(modelIDs, forKey: "aiModels") }
  }
  var instructions: String {
    didSet { defaults.set(instructions, forKey: "aiInstructions") }
  }
  var followsRepositoryRules: Bool {
    didSet { defaults.set(followsRepositoryRules, forKey: "aiRepositoryRules") }
  }

  private(set) var models: [AIModel] = []
  private(set) var isLoadingModels = false
  private(set) var modelsError: String?
  /// Bumped when a key is saved, so views that show key state refresh.
  private(set) var keyRevision = 0

  private let defaults = UserDefaults.standard

  private init() {
    isEnabled = defaults.bool(forKey: "aiEnabled")
    provider = defaults.string(forKey: "aiProvider").flatMap(AIProvider.init(rawValue:)) ?? .openCodeZen
    modelIDs = defaults.dictionary(forKey: "aiModels") as? [String: String] ?? [:]
    instructions = defaults.string(forKey: "aiInstructions") ?? ""
    followsRepositoryRules = defaults.object(forKey: "aiRepositoryRules") as? Bool ?? true
  }

  var modelID: String? {
    get { modelIDs[provider.rawValue] }
    set { modelIDs[provider.rawValue] = newValue }
  }

  var apiKey: String? {
    _ = keyRevision
    return Keychain.key(for: provider)
  }

  func saveKey(_ key: String) {
    Keychain.setKey(key, for: provider)
    keyRevision += 1
  }

  /// Ready to generate: switched on, with a key and a model.
  var isReady: Bool {
    isEnabled && apiKey?.isEmpty == false && modelID != nil
  }

  /// What's missing, in words, when not ready.
  var setupHint: String {
    if !isEnabled { return "Turn on AI commit messages in Settings (⌘,)." }
    if apiKey?.isEmpty != false { return "Add your \(provider.name) API key in Settings (⌘,)." }
    return "Pick a free model in Settings (⌘,)."
  }

  func loadModels() {
    let provider = self.provider
    isLoadingModels = true
    modelsError = nil
    Task {
      defer { isLoadingModels = false }
      do {
        let loaded = try await AIClient.freeModels(for: provider)
        guard provider == self.provider else { return }
        models = loaded
        // Keep the pick if it's still offered; free lineups change often.
        if let id = modelID, !loaded.contains(where: { $0.id == id }) { modelID = nil }
        if modelID == nil { modelID = loaded.first?.id }
      } catch {
        guard provider == self.provider else { return }
        models = []
        modelsError = "\(error)"
      }
    }
  }
}
