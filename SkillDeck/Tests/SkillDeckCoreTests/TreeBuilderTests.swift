import XCTest
@testable import SkillDeckCore

final class TreeBuilderTests: XCTestCase {
    private func skill(_ name: String, plugin: String?, scope: SourceScope = .user,
                       kind: ItemKind = .skill) -> SkillItem {
        SkillItem(name: name, kind: kind, scope: scope, pluginName: plugin,
                  description: "d-\(name)", body: "b", filePath: "/f/\(name)",
                  insertText: kind == .skill ? "use the \(name) skill" : "/\(name)")
    }

    func test_installed_plugin_skill_hangs_under_plugin_node() {
        let mpNodes = [
            Node(id: Node.marketplaceID("official"), kind: .marketplace, name: "official",
                 description: "", status: .notApplicable, parentID: nil),
            Node(id: Node.pluginID(marketplace: "official", plugin: "superpowers"),
                 kind: .plugin, name: "superpowers", description: "", status: .installed,
                 parentID: Node.marketplaceID("official"),
                 marketplaceName: "official", installRef: "superpowers@official"),
        ]
        let items = [skill("brainstorming", plugin: "superpowers")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: mpNodes)

        let leaf = nodes.first { $0.name == "brainstorming" }!
        XCTAssertEqual(leaf.kind, .skill)
        XCTAssertEqual(leaf.parentID, Node.pluginID(marketplace: "official", plugin: "superpowers"))
        XCTAssertEqual(leaf.insertText, "use the brainstorming skill")
        XCTAssertEqual(leaf.id, "user|superpowers|skill|brainstorming")
    }

    func test_local_skill_hangs_under_local_root() {
        let items = [skill("cloudflare", plugin: nil)]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "cloudflare" }!
        XCTAssertEqual(leaf.kind, .localSkill)
        XCTAssertEqual(leaf.parentID, "root|local")
        XCTAssertNotNil(nodes.first { $0.id == "root|local" })
    }

    func test_builtin_hangs_under_builtin_root() {
        let items = [SkillItem(name: "clear", kind: .builtinCommand, scope: .builtin,
                               pluginName: nil, description: "", body: "", filePath: nil,
                               insertText: "/clear")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "clear" }!
        XCTAssertEqual(leaf.kind, .builtinCommand)
        XCTAssertEqual(leaf.parentID, "root|builtin")
    }

    func test_project_item_hangs_under_project_root() {
        let items = [skill("deploy", plugin: nil, scope: .project("myapp"), kind: .command)]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "deploy" }!
        XCTAssertEqual(leaf.kind, .command)
        XCTAssertEqual(leaf.parentID, "root|project")
    }

    func test_dedupe_by_id() {
        let items = [skill("brainstorming", plugin: "superpowers"),
                     skill("brainstorming", plugin: "superpowers")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        XCTAssertEqual(nodes.filter { $0.name == "brainstorming" }.count, 1)
    }

    func test_plugin_skill_without_marketplace_node_still_appears() {
        let items = [skill("tdd", plugin: "superpowers")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let leaf = nodes.first { $0.name == "tdd" }!
        XCTAssertEqual(leaf.parentID, "plugin|superpowers")
        XCTAssertNotNil(nodes.first { $0.id == "plugin|superpowers" && $0.kind == .plugin })
    }
}
