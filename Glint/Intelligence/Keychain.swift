import Foundation
import Security

/// API keys for AI providers, in the login Keychain. Never in UserDefaults,
/// never in the repository.
enum Keychain {
  private static let service = "com.kerustudios.glint.ai"
  /// Where Glint kept keys when it was called Adit.
  private static let oldService = "com.kerustudios.adit.ai"

  /// What reading a key found. `refused` is not the same as `missing`: the
  /// key is there, but macOS wouldn't hand it over (a locked keychain, a
  /// declined prompt, or a build signed differently from the one that saved
  /// it). Glint mustn't ask for a new key then.
  enum Lookup: Equatable {
    case found(String)
    case missing
    case refused(OSStatus)
  }

  /// The saved key. One saved under Adit's name is copied over the first
  /// time it's read, so a key survives the rename.
  static func key(for provider: AIProvider) -> Lookup {
    let current = read(provider, from: service)
    guard current == .missing else { return current }
    let old = read(provider, from: oldService)
    if case .found(let key) = old { setKey(key, for: provider) }
    return old
  }

  /// Whether a key is saved, without reading it: attributes only, so macOS
  /// never asks for permission here.
  static func hasKey(for provider: AIProvider) -> Bool {
    [service, oldService].contains { service in
      let query: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: service,
        kSecAttrAccount: provider.rawValue,
        kSecReturnAttributes: true,
        kSecMatchLimit: kSecMatchLimitOne,
      ]
      var result: CFTypeRef?
      return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
  }

  private static func read(_ provider: AIProvider, from service: String) -> Lookup {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: provider.rawValue,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status != errSecItemNotFound else { return .missing }
    guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8)
    else { return .refused(status) }
    return key.isEmpty ? .missing : .found(key)
  }

  /// Saves `key`, or removes it when empty.
  @discardableResult
  static func setKey(_ key: String, for provider: AIProvider) -> Bool {
    let match: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: provider.rawValue,
    ]
    SecItemDelete(match as CFDictionary)
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    var item = match
    item[kSecValueData] = Data(trimmed.utf8)
    item[kSecAttrLabel] = "Glint: \(provider.name) API key"
    return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
  }
}
