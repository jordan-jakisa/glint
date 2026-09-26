import Foundation

/// Hosted model providers that offer free models, all spoken to through the
/// OpenAI-compatible chat completions API. Adit only lists their free models.
enum AIProvider: String, CaseIterable, Identifiable, Sendable {
  case openCodeZen, vercel, openRouter

  var id: String { rawValue }

  var name: String {
    switch self {
    case .openCodeZen: "OpenCode Zen"
    case .vercel: "Vercel AI Gateway"
    case .openRouter: "OpenRouter"
    }
  }

  var baseURL: URL {
    switch self {
    case .openCodeZen: URL(string: "https://opencode.ai/zen/v1")!
    case .vercel: URL(string: "https://ai-gateway.vercel.sh/v1")!
    case .openRouter: URL(string: "https://openrouter.ai/api/v1")!
    }
  }

  var chatCompletionsURL: URL { baseURL.appendingPathComponent("chat/completions") }
  var modelsURL: URL { baseURL.appendingPathComponent("models") }

  /// Where you get a key. Every provider needs one, even for free models.
  var keyURL: URL {
    switch self {
    case .openCodeZen: URL(string: "https://opencode.ai/docs/zen/")!
    case .vercel: URL(string: "https://vercel.com/docs/ai-gateway/authentication-and-byok")!
    case .openRouter: URL(string: "https://openrouter.ai/settings/keys")!
    }
  }

  /// What the provider says about free models and your data, shown before you
  /// send a diff. Free tiers often pay for themselves with training data.
  var privacyNote: String {
    switch self {
    case .openCodeZen:
      "Several free Zen models say collected data may be used to improve the model."
    case .vercel:
      "Vercel routes requests to the model's provider. Check that provider's terms."
    case .openRouter:
      "Free OpenRouter models may log prompts and use them for training."
    }
  }

  /// Extra headers a provider wants. OpenRouter uses this to name the app.
  var extraHeaders: [String: String] {
    switch self {
    case .openRouter: ["X-Title": "Adit"]
    default: [:]
    }
  }

  /// Picks the free chat models out of a provider's `/models` response.
  func freeModels(from data: Data) throws -> [AIModel] {
    let listing = try JSONDecoder().decode(ModelListing.self, from: data)
    let models = listing.data.filter { isFreeChatModel($0) }
    return models.map { AIModel(id: $0.id, name: $0.name ?? $0.id) }
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  private func isFreeChatModel(_ model: ModelListing.Entry) -> Bool {
    switch self {
    case .openCodeZen:
      // Zen's listing has no prices. Free models are named that way, plus the
      // "big-pickle" stealth model. Jev and Muse models use other endpoints
      // than chat completions, so they're left out.
      let id = model.id
      let named = id.hasSuffix("-free") || id == "big-pickle"
      return named && !id.hasPrefix("jev-") && !id.hasPrefix("muse-")
    case .vercel:
      guard model.type == "language", let pricing = model.pricing else { return false }
      return Self.isZero(pricing.input) && Self.isZero(pricing.output)
    case .openRouter:
      guard let pricing = model.pricing else { return false }
      let text = model.architecture?.outputModalities?.contains("text") ?? true
      return text && Self.isZero(pricing.prompt) && Self.isZero(pricing.completion)
    }
  }

  private static func isZero(_ price: String?) -> Bool {
    guard let price, let value = Double(price) else { return false }
    return value == 0
  }
}

struct AIModel: Identifiable, Hashable, Codable, Sendable {
  let id: String
  let name: String
}

/// The parts of an OpenAI-style `/models` response Adit reads. Each provider
/// adds its own fields; all of them are optional here.
private struct ModelListing: Decodable {
  struct Entry: Decodable {
    let id: String
    let name: String?
    let type: String?
    let pricing: Pricing?
    let architecture: Architecture?
  }

  struct Pricing: Decodable {
    // OpenRouter
    let prompt: String?
    let completion: String?
    // Vercel
    let input: String?
    let output: String?
  }

  struct Architecture: Decodable {
    let outputModalities: [String]?

    enum CodingKeys: String, CodingKey {
      case outputModalities = "output_modalities"
    }
  }

  let data: [Entry]

  init(from decoder: Decoder) throws {
    // OpenCode Zen returns a bare array; the others wrap it in "data".
    if let array = try? [Entry](from: decoder) {
      data = array
    } else {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      data = try container.decode([Entry].self, forKey: .data)
    }
  }

  enum CodingKeys: String, CodingKey { case data }
}
