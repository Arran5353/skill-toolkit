import XCTest
@testable import SkillDeckCore

@MainActor
final class AppStoreNodeTests: XCTestCase {
    private func tmp() -> String {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json").path
    }
    private func nodes() -> [Node] {
        [
            Node(id: "mp|official", kind: .marketplace, name: "official", description: "",
                 status: .notApplicable, parentID: nil),
            Node(id: "mp|official|plugin|superpowers", kind: .plugin, name: "superpowers",
                 description: "", status: .installed, parentID: "mp|official",
                 marketplaceName: "official", installRef: "superpowers@official"),
            Node(id: "user|superpowers|skill|tdd", kind: .skill, name: "tdd", description: "d",
                 status: .notApplicable, parentID: "mp|official|plugin|superpowers",
                 body: "b", insertText: "use the tdd skill", filePath: "/x"),
        ]
    }

    func test_children_of_parent() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        XCTAssertEqual(store.children(of: "mp|official|plugin|superpowers").map(\.name), ["tdd"])
        XCTAssertEqual(store.children(of: "mp|official").map(\.name), ["superpowers"])
    }

    func test_root_nodes() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        XCTAssertEqual(store.rootNodes().map(\.id), ["mp|official"])
    }

    func test_favorite_only_leaves() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        store.toggleFavorite("mp|official|plugin|superpowers")  // plugin: ignored
        XCTAssertFalse(store.isFavorite("mp|official|plugin|superpowers"))
        store.toggleFavorite("user|superpowers|skill|tdd")      // leaf: allowed
        XCTAssertTrue(store.isFavorite("user|superpowers|skill|tdd"))
    }

    func test_effective_insert_text() {
        let store = AppStore(statePath: tmp())
        store.setNodes(nodes())
        XCTAssertEqual(store.effectiveInsertText(for: "user|superpowers|skill|tdd"), "use the tdd skill")
    }

    func test_fuzzy_search_ranks_name_match_first() {
        let store = AppStore(statePath: tmp())
        store.setNodes([
            Node(id: "a", kind: .skill, name: "brainstorming", description: "",
                 status: .notApplicable, parentID: nil, insertText: "use the brainstorming skill"),
            Node(id: "b", kind: .command, name: "build", description: "brainstorm helper",
                 status: .notApplicable, parentID: nil, insertText: "/build"),
        ])
        let r = store.fuzzySearch("brain")
        XCTAssertEqual(r.first?.name, "brainstorming")  // name match beats description match
    }
}
