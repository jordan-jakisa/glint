import Foundation

/// Glint was called Adit. The first launch after the rename brings over
/// Adit's settings (recent projects, layout, shortcuts, AI choices), so
/// nothing needs setting up again. API keys come over from the Keychain on
/// first use, in `Keychain.key(for:)`.
enum LegacyMigration {
  static let oldDomain = "com.kerustudios.adit"
  private static let doneKey = "migratedFromAdit"

  static func run(defaults: UserDefaults = .standard, from oldDomain: String = oldDomain) {
    guard !defaults.bool(forKey: doneKey) else { return }
    defer { defaults.set(true, forKey: doneKey) }
    guard let old = defaults.persistentDomain(forName: oldDomain) else { return }
    for (key, value) in old where defaults.object(forKey: key) == nil {
      defaults.set(value, forKey: key)
    }
  }
}
