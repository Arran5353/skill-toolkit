import XCTest
@testable import SkillDeckCore

final class InstalledPluginsIndexTests: XCTestCase {
    private func tmp(_ json: String) throws -> String {
        let p = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".json").path
        try json.write(toFile: p, atomically: true, encoding: .utf8)
        return p
    }

    func test_parses_install_refs_from_keys() throws {
        let path = try tmp("""
        {"version":2,"plugins":{
          "superpowers@claude-plugins-official":[{"scope":"user"}],
          "frontend-design@claude-plugins-official":[{"scope":"user"}]
        }}
        """)
        let idx = InstalledPluginsIndex.load(from: path)
        XCTAssertTrue(idx.contains("superpowers@claude-plugins-official"))
        XCTAssertTrue(idx.contains("frontend-design@claude-plugins-official"))
        XCTAssertEqual(idx.count, 2)
    }

    func test_missing_file_returns_empty() {
        XCTAssertTrue(InstalledPluginsIndex.load(from: "/nope/x.json").isEmpty)
    }

    func test_malformed_returns_empty() throws {
        let path = try tmp("not json")
        XCTAssertTrue(InstalledPluginsIndex.load(from: path).isEmpty)
    }
}
