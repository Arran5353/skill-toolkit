import XCTest
@testable import SkillDeckCore

final class CatalogLoaderTests: XCTestCase {
    func test_builds_nodes_from_scan_results() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        func write(_ rel: String, _ s: String) throws {
            let u = root.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try s.write(to: u, atomically: true, encoding: .utf8)
        }
        try write("skills/cloudflare/SKILL.md", "---\nname: cloudflare\ndescription: cf\n---\nbody")
        try write("plugins/cache/mp/superpowers/5.1.0/skills/tdd/SKILL.md",
                  "---\nname: tdd\ndescription: t\n---\nbody")
        try write("plugins/marketplaces/official/.claude-plugin/marketplace.json",
                  "{\"name\":\"official\",\"plugins\":[{\"name\":\"superpowers\",\"description\":\"d\"},{\"name\":\"ralph-loop\",\"description\":\"r\"}]}")
        try write("plugins/installed_plugins.json",
                  "{\"version\":2,\"plugins\":{\"superpowers@official\":[{}]}}")

        let result = CatalogLoader.load(
            userSkillsDir: root.appendingPathComponent("skills").path,
            pluginsCacheDir: root.appendingPathComponent("plugins/cache").path,
            marketplacesDir: root.appendingPathComponent("plugins/marketplaces").path,
            installedPluginsPath: root.appendingPathComponent("plugins/installed_plugins.json").path,
            projectDirs: [])

        XCTAssertNotNil(result.nodes.first { $0.id == "mp|official" })
        let sp = result.nodes.first { $0.kind == .plugin && $0.name == "superpowers" }!
        XCTAssertEqual(sp.status, .installed)
        XCTAssertEqual(result.nodes.first { $0.name == "ralph-loop" }?.status, .available)
        XCTAssertEqual(result.nodes.first { $0.name == "cloudflare" }?.parentID, "root|local")
    }
}
