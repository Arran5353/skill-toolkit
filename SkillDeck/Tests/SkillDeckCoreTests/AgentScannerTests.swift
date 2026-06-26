import XCTest
@testable import SkillDeckCore
import Foundation

final class AgentScannerTests: XCTestCase {
    private func tmp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func write(_ base: URL, _ rel: String, _ s: String) throws {
        let u = base.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try s.write(to: u, atomically: true, encoding: .utf8)
    }

    func test_scans_standard_agents_dir() throws {
        let d = try tmp()
        try write(d, "agents/reviewer.md", "---\nname: reviewer\ndescription: reviews code\nmodel: opus\n---\nbody")
        try write(d, "agents/tester.md", "---\nname: tester\ndescription: writes tests\n---\nbody")
        let a = AgentScanner.scan(pluginVersionDir: d.path)
        XCTAssertEqual(a.map(\.name), ["reviewer", "tester"])
        XCTAssertEqual(a.first(where: { $0.name == "reviewer" })?.model, "opus")
        XCTAssertNil(a.first(where: { $0.name == "tester" })?.model)
    }

    func test_scans_plugin_json_declared_agent() throws {
        let d = try tmp()
        try write(d, ".claude-plugin/plugin.json", "{\"name\":\"p\",\"agents\":[\"./custom/special.md\"]}")
        try write(d, "custom/special.md", "---\nname: special\ndescription: a special agent\n---\nx")
        let a = AgentScanner.scan(pluginVersionDir: d.path)
        XCTAssertTrue(a.contains { $0.name == "special" })
    }

    func test_name_falls_back_to_filename() throws {
        let d = try tmp()
        try write(d, "agents/noname.md", "---\ndescription: no name field\n---\nbody")
        let a = AgentScanner.scan(pluginVersionDir: d.path)
        XCTAssertTrue(a.contains { $0.name == "noname" })
    }

    func test_missing_returns_empty() throws {
        XCTAssertTrue(AgentScanner.scan(pluginVersionDir: "/nope").isEmpty)
    }
}
