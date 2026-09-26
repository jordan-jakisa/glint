import Foundation
import Testing

@testable import Glint

@Suite struct LegacyMigrationTests {
  @Test func bringsOverSettingsOnceWithoutOverwriting() throws {
    let suite = "LegacyMigrationTests.\(UUID().uuidString)"
    let old = "LegacyMigrationTests.old.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer {
      defaults.removePersistentDomain(forName: suite)
      defaults.removePersistentDomain(forName: old)
    }
    defaults.setPersistentDomain(["layout": "split", "fileOrder": "path"], forName: old)
    defaults.set("smart", forKey: "fileOrder")

    LegacyMigration.run(defaults: defaults, from: old)
    #expect(defaults.string(forKey: "layout") == "split")
    #expect(defaults.string(forKey: "fileOrder") == "smart")

    defaults.removeObject(forKey: "layout")
    LegacyMigration.run(defaults: defaults, from: old)
    #expect(defaults.string(forKey: "layout") == nil)
  }
}
