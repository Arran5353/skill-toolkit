import XCTest
@testable import SkillDeckCore

final class PersistenceTests: XCTestCase {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
    }

    func test_round_trip_preserves_state() throws {
        let path = tempPath()
        var state = PersistedState()
        state.favorites = ["user|superpowers|skill|brainstorming"]
        state.recents = [RecentEntry(id: "a", lastUsed: 123.0, count: 7)]
        state.overrides = ["a": "use the a skill"]
        try Persistence.save(state, to: path)

        let loaded = try Persistence.load(from: path)
        XCTAssertEqual(loaded, state)
    }

    func test_load_missing_file_returns_empty_state() throws {
        let loaded = try Persistence.load(from: "/nope/missing.json")
        XCTAssertEqual(loaded, PersistedState())
    }

    func test_favorites_survive_plugin_path_change() throws {
        let path = tempPath()
        var state = PersistedState()
        state.favorites = ["user|superpowers|skill|brainstorming"]
        try Persistence.save(state, to: path)
        let loaded = try Persistence.load(from: path)
        XCTAssertTrue(loaded.favorites.contains("user|superpowers|skill|brainstorming"))
    }
}
