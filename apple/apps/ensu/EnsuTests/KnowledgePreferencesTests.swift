import XCTest
@testable import Ensu

final class KnowledgePreferencesTests: XCTestCase {
    func testPackSettingsMigrationPreservesLegacyChoicesAndLaterChanges() throws {
        let suite = "KnowledgePreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = KnowledgePreferences(defaults: defaults)
        let legacyKey = "ensu.knowledge.enabled_dataset_ids"
        let settingsKey = "ensu.packs.disabledByDefault"
        let available: Set<String> = ["wiki", "books"]
        for enabled in [[], ["wiki"]] {
            defaults.removeObject(forKey: settingsKey)
            defaults.set(enabled, forKey: legacyKey)
            XCTAssertEqual(
                preferences.migratePackSettings(availablePackIDs: available),
                available.subtracting(enabled))
            preferences.setDatasetEnabled(id: "wiki", enabled: false)
            preferences.setDatasetEnabled(id: "books", enabled: true)
            XCTAssertEqual(
                KnowledgePreferences(defaults: defaults)
                    .migratePackSettings(availablePackIDs: available.union(["new-pack"])),
                ["wiki"])
        }
        defaults.removeObject(forKey: settingsKey)
        defaults.removeObject(forKey: legacyKey)
        XCTAssertEqual(preferences.migratePackSettings(availablePackIDs: available), [])
    }
}
