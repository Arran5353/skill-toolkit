import XCTest
@testable import SkillDeckCore

final class SkillItemTests: XCTestCase {
    func test_id_is_stable_and_ignores_file_path() {
        let a = SkillItem(name: "brainstorming", kind: .skill, scope: .user,
                          pluginName: "superpowers", description: "d", body: "b",
                          filePath: "/old/5.1.0/SKILL.md", insertText: "x")
        let b = SkillItem(name: "brainstorming", kind: .skill, scope: .user,
                          pluginName: "superpowers", description: "d2", body: "b2",
                          filePath: "/new/6.0.0/SKILL.md", insertText: "y")
        XCTAssertEqual(a.id, b.id)
        XCTAssertEqual(a.id, "user|superpowers|skill|brainstorming")
    }

    func test_id_for_project_and_nil_plugin() {
        let item = SkillItem(name: "deploy", kind: .command, scope: .project("paperwork"),
                             pluginName: nil, description: "", body: "",
                             filePath: nil, insertText: "/deploy")
        XCTAssertEqual(item.id, "project:paperwork|_|command|deploy")
    }
}
