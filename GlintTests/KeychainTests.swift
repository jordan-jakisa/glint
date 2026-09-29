import Foundation
import Security
import Testing

@testable import Glint

/// The Keychain against the real login keychain, on throwaway items. A key
/// must survive being read, however often and whichever keychain this build
/// can use: a read once deleted the key it had just read.
@MainActor @Suite(.serialized) struct KeychainTests {
  private func withTestServices(_ body: () throws -> Void) rethrows {
    let (service, old) = (Keychain.service, Keychain.oldService)
    let id = UUID().uuidString
    Keychain.service = "com.kerustudios.glint.test.\(id)"
    Keychain.oldService = "com.kerustudios.glint.test-old.\(id)"
    defer {
      Keychain.setKey("", for: .openRouter)
      Keychain.service = service
      Keychain.oldService = old
    }
    try body()
  }

  @Test func aSavedKeySurvivesRepeatedReads() throws {
    try withTestServices {
      #expect(Keychain.setKey("sk-test-123", for: .openRouter))
      for _ in 0..<3 {
        #expect(Keychain.key(for: .openRouter) == .found("sk-test-123"))
        #expect(Keychain.hasKey(for: .openRouter))
      }
    }
  }

  @Test func aKeyUnderTheOldNameIsReadAndKept() throws {
    try withTestServices {
      // Saved the way an old build did: straight into the login keychain.
      let item: [CFString: Any] = [
        kSecClass: kSecClassGenericPassword, kSecAttrService: Keychain.oldService,
        kSecAttrAccount: AIProvider.openRouter.rawValue, kSecValueData: Data("sk-old".utf8),
      ]
      #expect(SecItemAdd(item as CFDictionary, nil) == errSecSuccess)
      defer {
        SecItemDelete(
          [kSecClass: kSecClassGenericPassword, kSecAttrService: Keychain.oldService] as CFDictionary)
      }
      #expect(Keychain.key(for: .openRouter) == .found("sk-old"))
      // Still there on the next read, wherever it now lives.
      #expect(Keychain.key(for: .openRouter) == .found("sk-old"))
      #expect(Keychain.hasKey(for: .openRouter))
    }
  }

  @Test func savingEmptyRemovesTheKey() throws {
    try withTestServices {
      Keychain.setKey("sk-test", for: .openRouter)
      Keychain.setKey("", for: .openRouter)
      #expect(Keychain.key(for: .openRouter) == .missing)
      #expect(!Keychain.hasKey(for: .openRouter))
    }
  }
}
