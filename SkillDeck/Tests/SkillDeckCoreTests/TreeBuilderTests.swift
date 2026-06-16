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

    func test_project_root_label_includes_project_name() {
        let item = SkillItem(name: "impeccable", kind: .skill, scope: .project("Desktop/Cocktail-expert"),
                             pluginName: nil, description: "", body: "", filePath: "/x",
                             insertText: "use the impeccable skill")
        let nodes = TreeBuilder.build(skillItems: [item], marketplaceNodes: [])
        let root = nodes.first { $0.id == TreeBuilder.projectRootID }!
        XCTAssertTrue(root.name.contains("Cocktail-expert"))
    }

    func test_project_root_label_multiple_projects() {
        let items = [
            SkillItem(name: "a", kind: .skill, scope: .project("Desktop/Proj-A"),
                      pluginName: nil, description: "", body: "", filePath: "/a",
                      insertText: "use the a skill"),
            SkillItem(name: "b", kind: .skill, scope: .project("Desktop/Proj-B"),
                      pluginName: nil, description: "", body: "", filePath: "/b",
                      insertText: "use the b skill"),
        ]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: [])
        let root = nodes.first { $0.id == TreeBuilder.projectRootID }!
        XCTAssertTrue(root.name.contains("2"), "Expected count in label, got: \(root.name)")
    }

    func test_skill_subcommands_become_child_nodes() {
        let item = SkillItem(name: "impeccable", kind: .skill, scope: .user, pluginName: "impeccable",
                             description: "", body: "", filePath: "/x",
                             insertText: "use the impeccable skill",
                             argumentHint: "[craft|polish] [target]")
        let nodes = TreeBuilder.build(skillItems: [item], marketplaceNodes: [])
        let skill = nodes.first { $0.name == "impeccable" && $0.kind == .skill }!
        let subs = nodes.filter { $0.parentID == skill.id && $0.kind == .command }
        XCTAssertEqual(Set(subs.map { $0.name }), ["craft", "polish"])
        let craft = subs.first { $0.name == "craft" }!
        XCTAssertEqual(craft.insertText, "/impeccable craft")
    }

    func test_same_named_plugins_across_marketplaces_documents_current_behavior() {
        // Two marketplaces each declare a plugin named "shared". A leaf for "shared" is parented
        // to ONE of them (last-write-wins on the name index). This documents current behavior;
        // see the KNOWN LIMITATION note in TreeBuilder.
        let mpNodes = [
            Node(id: Node.marketplaceID("mpA"), kind: .marketplace, name: "mpA",
                 description: "", status: .notApplicable, parentID: nil),
            Node(id: Node.pluginID(marketplace: "mpA", plugin: "shared"), kind: .plugin,
                 name: "shared", description: "", status: .installed,
                 parentID: Node.marketplaceID("mpA"), marketplaceName: "mpA", installRef: "shared@mpA"),
            Node(id: Node.marketplaceID("mpB"), kind: .marketplace, name: "mpB",
                 description: "", status: .notApplicable, parentID: nil),
            Node(id: Node.pluginID(marketplace: "mpB", plugin: "shared"), kind: .plugin,
                 name: "shared", description: "", status: .installed,
                 parentID: Node.marketplaceID("mpB"), marketplaceName: "mpB", installRef: "shared@mpB"),
        ]
        let items = [skill("foo", plugin: "shared")]
        let nodes = TreeBuilder.build(skillItems: items, marketplaceNodes: mpNodes)
        let leaf = nodes.first { $0.name == "foo" }!
        // last-write-wins: parented to mpB's plugin node
        XCTAssertEqual(leaf.parentID, Node.pluginID(marketplace: "mpB", plugin: "shared"))
    }
}
