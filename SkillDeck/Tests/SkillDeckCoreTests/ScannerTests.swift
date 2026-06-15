import XCTest
@testable import SkillDeckCore

final class ScannerTests: XCTestCase {
    private func makeTree() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        func write(_ rel: String, _ contents: String) throws {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("skills/brainstorming/SKILL.md",
                  "---\nname: brainstorming\ndescription: BS\n---\nbody bs")
        try write("plugins/cache/mp/superpowers/5.1.0/skills/tdd/SKILL.md",
                  "---\nname: tdd\ndescription: TDD\n---\nbody tdd")
        try write("plugins/cache/mp/superpowers/5.1.0/commands/cr.md",
                  "---\ndescription: Code review\n---\nbody cr")
        return root
    }

    func test_scans_user_plugin_skills_and_commands() throws {
        let root = try makeTree()
        let result = Scanner.scan(
            userSkillsDir: root.appendingPathComponent("skills").path,
            pluginsCacheDir: root.appendingPathComponent("plugins/cache").path,
            projectDirs: [],
            includeBuiltins: false
        )
        let names = Set(result.items.map { $0.name })
        XCTAssertEqual(names, ["brainstorming", "tdd", "cr"])

        let tdd = result.items.first { $0.name == "tdd" }!
        XCTAssertEqual(tdd.pluginName, "superpowers")
        XCTAssertEqual(tdd.kind, .skill)
        XCTAssertEqual(tdd.scope, .user)

        let cr = result.items.first { $0.name == "cr" }!
        XCTAssertEqual(cr.kind, .command)
        XCTAssertEqual(cr.pluginName, "superpowers")
        XCTAssertEqual(cr.insertText, "/cr")

        let top = result.items.first { $0.name == "brainstorming" }!
        XCTAssertNil(top.pluginName)
        XCTAssertEqual(top.insertText, "use the brainstorming skill")
    }

    func test_command_name_falls_back_to_filename() throws {
        let root = try makeTree()
        let result = Scanner.scan(
            userSkillsDir: root.appendingPathComponent("skills").path,
            pluginsCacheDir: root.appendingPathComponent("plugins/cache").path,
            projectDirs: [], includeBuiltins: false
        )
        XCTAssertNotNil(result.items.first { $0.name == "cr" })
    }

    func test_project_scope_items() throws {
        let fm = FileManager.default
        let proj = fm.temporaryDirectory.appendingPathComponent("proj-" + UUID().uuidString)
        let cmd = proj.appendingPathComponent(".claude/commands/deploy.md")
        try fm.createDirectory(at: cmd.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\ndescription: Deploy\n---\nrun it".write(to: cmd, atomically: true, encoding: .utf8)

        let result = Scanner.scan(userSkillsDir: "/nope", pluginsCacheDir: "/nope",
                                  projectDirs: [proj.path], includeBuiltins: false)
        let deploy = result.items.first { $0.name == "deploy" }!
        let purl = URL(fileURLWithPath: proj.path)
        let pparent = purl.deletingLastPathComponent().lastPathComponent
        let expected = pparent.isEmpty ? purl.lastPathComponent : "\(pparent)/\(purl.lastPathComponent)"
        XCTAssertEqual(deploy.scope, .project(expected))
        XCTAssertEqual(deploy.insertText, "/deploy")
    }

    func test_multiple_plugin_versions_dedupe_keeps_highest() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        func write(_ rel: String, _ contents: String) throws {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("cache/mp/superpowers/5.1.0/skills/tdd/SKILL.md",
                  "---\nname: tdd\ndescription: OLD\n---\nold")
        try write("cache/mp/superpowers/6.0.0/skills/tdd/SKILL.md",
                  "---\nname: tdd\ndescription: NEW\n---\nnew")
        let result = Scanner.scan(userSkillsDir: "/nope",
                                  pluginsCacheDir: root.appendingPathComponent("cache").path,
                                  projectDirs: [], includeBuiltins: false)
        let tdds = result.items.filter { $0.name == "tdd" }
        XCTAssertEqual(tdds.count, 1)
        XCTAssertEqual(tdds.first?.description, "NEW")
    }

    func test_empty_file_records_warning_not_crash() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = root.appendingPathComponent("skills/broken/SKILL.md")
        try fm.createDirectory(at: s.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "".write(to: s, atomically: true, encoding: .utf8)
        let result = Scanner.scan(userSkillsDir: root.appendingPathComponent("skills").path,
                                  pluginsCacheDir: "/nope", projectDirs: [], includeBuiltins: false)
        XCTAssertNotNil(result.items.first { $0.name == "broken" })
        XCTAssertFalse(result.warnings.isEmpty)
    }
}
