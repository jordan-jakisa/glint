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

  /// Whether each provider has a key saved: true, false, or missing when
  /// Adit hasn't checked yet (keys saved before this was tracked). Not
  /// secret, so it lives in UserDefaults: checking it never touches the
  /// Keychain, which on macOS can ask for your login password.
  private(set) var keyState: [String: Bool] {
    didSet { defaults.set(keyState, forKey: "aiKeyState") }
  }

  private(set) var models: [AIModel] = []
  private(set) var isLoadingModels = false
  private(set) var modelsError: String?
  /// Keys already read this launch, so the Keychain is asked at most once.
  @ObservationIgnored private var keyCache: [AIProvider: String] = [:]

  private let defaults = UserDefaults.standard

  private init() {
    isEnabled = defaults.bool(forKey: "aiEnabled")
    provider = defaults.string(forKey: "aiProvider").flatMap(AIProvider.init(rawValue:)) ?? .openCodeZen
    modelIDs = defaults.dictionary(forKey: "aiModels") as? [String: String] ?? [:]
    instructions = defaults.string(forKey: "aiInstructions") ?? ""
    followsRepositoryRules = defaults.object(forKey: "aiRepositoryRules") as? Bool ?? true
    keyState = defaults.dictionary(forKey: "aiKeyState") as? [String: Bool] ?? [:]
  }

  var modelID: String? {
    get { modelIDs[provider.rawValue] }
    set { modelIDs[provider.rawValue] = newValue }
  }

  var hasKey: Bool { keyState[provider.rawValue] == true }

  /// A key may have been saved before Adit tracked it; the first real use
  /// finds out.
  var keyUnchecked: Bool { keyState[provider.rawValue] == nil }

  /// Reads the key from the Keychain. Only call this when about to send a
  /// request: it's the one place that can make macOS ask for permission.
  func readKey() -> String? {
    if let cached = keyCache[provider] { return cached }
    let key = Keychain.key(for: provider).flatMap { $0.isEmpty ? nil : $0 }
    keyState[provider.rawValue] = key != nil
    keyCache[provider] = key
    return key
  }

  func saveKey(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    Keychain.setKey(trimmed, for: provider)
    keyCache[provider] = trimmed.isEmpty ? nil : trimmed
    keyState[provider.rawValue] = !trimmed.isEmpty
  }

  /// Ready to generate: switched on, with a key and a model. Never reads the
  /// Keychain, so it's safe to check while drawing.
  var isReady: Bool {
    isEnabled && modelID != nil && (hasKey || keyUnchecked)
  }

  /// What's missing, in words, when not ready.
  var setupHint: String {
    if !isEnabled { return "Turn on AI commit messages in Settings (⌘,)." }
    if !hasKey { return "Add your \(provider.name) API key in Settings (⌘,)." }
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
