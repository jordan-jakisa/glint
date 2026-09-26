import Foundation
import Security

/// API keys for AI providers, in the login Keychain. Never in UserDefaults,
/// never in the repository.
enum Keychain {
  private static let service = "com.kerustudios.adit.ai"

  static func key(for provider: AIProvider) -> String? {
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: provider.rawValue,
      kSecReturnData: true,
      kSecMatchLimit: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
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
    item[kSecAttrLabel] = "Adit: \(provider.name) API key"
    return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
  }
}
