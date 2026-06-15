import XCTest
@testable import SkillDeckCore

@MainActor
final class AppStoreTests: XCTestCase {
    private func tempPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
    }

    private func sampleItems() -> [SkillItem] {
        [
            SkillItem(name: "brainstorming", kind: .skill, scope: .user, pluginName: "sp",
                      description: "creative", body: "", filePath: "/a", insertText: "use the brainstorming skill"),
            SkillItem(name: "code-review", kind: .command, scope: .user, pluginName: "cr",
                      description: "review diff", body: "", filePath: "/b", insertText: "/code-review"),
        ]
    }

    func test_toggle_favorite_persists() throws {
        let path = tempPath()
        let store = AppStore(statePath: path)
        store.setItems(sampleItems())
        let id = "user|sp|skill|brainstorming"
        store.toggleFavorite(id)
        XCTAssertTrue(store.isFavorite(id))

        let reloaded = AppStore(statePath: path)
        XCTAssertTrue(reloaded.state.favorites.contains(id))
    }

    func test_record_use_updates_recents_count_and_order() {
        let store = AppStore(statePath: tempPath())
        store.setItems(sampleItems())
        store.recordUse("user|cr|command|code-review", now: 1.0)
        store.recordUse("user|sp|skill|brainstorming", now: 2.0)
        store.recordUse("user|cr|command|code-review", now: 3.0)
        let recents = store.recentItems(limit: 10)
        XCTAssertEqual(recents.first?.name, "code-review") // most recent
        XCTAssertEqual(store.useCount("user|cr|command|code-review"), 2)
    }

    func test_search_matches_name_description_plugin() {
        let store = AppStore(statePath: tempPath())
        store.setItems(sampleItems())
        XCTAssertEqual(store.search("brain").map(\.name), ["brainstorming"])
        XCTAssertEqual(store.search("review").map(\.name), ["code-review"])
        XCTAssertEqual(Set(store.search("").map(\.name)), ["brainstorming", "code-review"])
    }

    func test_empty_override_clears_and_restores_default() {
        let store = AppStore(statePath: tempPath())
        store.setItems(sampleItems())
        let id = "user|sp|skill|brainstorming"
        store.setOverride(id, text: "/custom")
        XCTAssertEqual(store.effectiveInsertText(for: id), "/custom")
        store.setOverride(id, text: "   ")  // whitespace-only clears it
        XCTAssertEqual(store.effectiveInsertText(for: id), "use the brainstorming skill")
        store.setOverride(id, text: "/again")
        store.removeOverride(id)
        XCTAssertEqual(store.effectiveInsertText(for: id), "use the brainstorming skill")
    }

    func test_override_changes_effective_insert_text() {
        let path = tempPath()
        let store = AppStore(statePath: path)
        store.setItems(sampleItems())
        let id = "user|sp|skill|brainstorming"
        store.setOverride(id, text: "/brainstorm")
        XCTAssertEqual(store.effectiveInsertText(for: id), "/brainstorm")

        let reloaded = AppStore(statePath: path)
        reloaded.setItems(sampleItems())
        XCTAssertEqual(reloaded.effectiveInsertText(for: id), "/brainstorm")
    }
}
