import Foundation
import Security

/// API keys for AI providers, in the Keychain. Never in UserDefaults,
/// never in the repository.
///
/// Keys live in the data protection keychain, the one iOS uses. Access to an
/// item there comes from the app's team (the `keychain-access-groups`
/// entitlement), not from a list of trusted app signatures, so every build
/// signed by the team reads it without macOS asking, and a declined prompt
/// can't lock you out. Keys an older build left in the login keychain are
/// moved over the first time they're read.
enum Keychain {
  private static let service = "com.kerustudios.glint.ai"
  /// Where Glint kept keys when it was called Adit.
  private static let oldService = "com.kerustudios.adit.ai"

  /// What reading a key found. `refused` is not the same as `missing`: the
  /// key is there, but macOS wouldn't hand it over. Glint mustn't claim
  /// there's no key then.
  enum Lookup: Equatable {
    case found(String)
    case missing
    case refused(OSStatus)
  }

  /// The saved key: from the data protection keychain, else from the login
  /// keychain (moved over on the way).
  static func key(for provider: AIProvider) -> Lookup {
    let current = read(provider, service: service, modern: true)
    guard current == .missing else { return current }
    for legacy in [service, oldService] {
      let found = read(provider, service: legacy, modern: false)
      switch found {
      case .missing: continue
      case .found(let key):
        if setKey(key, for: provider) { deleteLegacy(provider) }
        return found
      case .refused: return found
      }
    }
    return .missing
  }

  /// Whether a key is saved, without reading it: attributes only, so macOS
  /// never asks for permission here.
  static func hasKey(for provider: AIProvider) -> Bool {
    [(service, true), (service, false), (oldService, false)].contains { service, modern in
      var query = base(provider, service: service, modern: modern)
      query[kSecReturnAttributes] = true
      query[kSecMatchLimit] = kSecMatchLimitOne
      var result: CFTypeRef?
      return SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess
    }
  }

  /// Saves `key`, or removes it when empty. Falls back to the login
  /// keychain only if this build can't use the data protection one (an
  /// unsigned build has no team).
  @discardableResult
  static func setKey(_ key: String, for provider: AIProvider) -> Bool {
    let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
    SecItemDelete(base(provider, service: service, modern: true) as CFDictionary)
    guard !trimmed.isEmpty else {
      deleteLegacy(provider)
      return true
    }
    for modern in [true, false] {
      var item = base(provider, service: service, modern: modern)
      item[kSecValueData] = Data(trimmed.utf8)
      item[kSecAttrLabel] = "Glint: \(provider.name) API key"
      // Readable whenever you're logged in; never synced to other Macs.
      item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      if !modern { SecItemDelete(base(provider, service: service, modern: false) as CFDictionary) }
      let status = SecItemAdd(item as CFDictionary, nil)
      if status == errSecSuccess {
        if modern { deleteLegacy(provider) }
        return true
      }
      Timing.log.error("Keychain save failed: \(status) (modern: \(modern))")
      if status != errSecMissingEntitlement { return false }
    }
    return false
  }

  private static func base(_ provider: AIProvider, service: String, modern: Bool) -> [CFString: Any] {
    var query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: service,
      kSecAttrAccount: provider.rawValue,
    ]
    if modern { query[kSecUseDataProtectionKeychain] = true }
    return query
  }

  private static func read(_ provider: AIProvider, service: String, modern: Bool) -> Lookup {
    var query = base(provider, service: service, modern: modern)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    // An unsigned build can't see the data protection keychain at all.
    if status == errSecItemNotFound || (modern && status == errSecMissingEntitlement) { return .missing }
    guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8)
    else {
      Timing.log.error("Keychain read refused: \(status) (modern: \(modern))")
      return .refused(status)
    }
    return key.isEmpty ? .missing : .found(key)
  }

  private static func deleteLegacy(_ provider: AIProvider) {
    for legacy in [service, oldService] {
      SecItemDelete(base(provider, service: legacy, modern: false) as CFDictionary)
    }
  }
}
