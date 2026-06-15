import XCTest
@testable import SkillDeckCore

final class MarketplaceScannerTests: XCTestCase {
    private func makeMarketplaces(_ specs: [(String, [String])]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        for (mp, plugins) in specs {
            let dir = root.appendingPathComponent("\(mp)/.claude-plugin")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let entries = plugins.map { "{\"name\":\"\($0)\",\"description\":\"desc \($0)\"}" }
                .joined(separator: ",")
            let json = "{\"name\":\"\(mp)\",\"plugins\":[\(entries)]}"
            try json.write(to: dir.appendingPathComponent("marketplace.json"),
                           atomically: true, encoding: .utf8)
        }
        return root
    }

    func test_scans_marketplaces_and_plugins_with_status() throws {
        let root = try makeMarketplaces([("official", ["superpowers", "ralph-loop"])])
        let installed: Set<String> = ["superpowers@official"]
        let result = MarketplaceScanner.scan(marketplacesDir: root.path, installed: installed)

        let mp = result.nodes.first { $0.kind == .marketplace }!
        XCTAssertEqual(mp.name, "official")
        XCTAssertEqual(mp.id, "mp|official")

        let sp = result.nodes.first { $0.kind == .plugin && $0.name == "superpowers" }!
        XCTAssertEqual(sp.parentID, "mp|official")
        XCTAssertEqual(sp.installRef, "superpowers@official")
        XCTAssertEqual(sp.status, .installed)
        XCTAssertEqual(sp.id, "mp|official|plugin|superpowers")

        let rl = result.nodes.first { $0.kind == .plugin && $0.name == "ralph-loop" }!
        XCTAssertEqual(rl.status, .available)
        XCTAssertEqual(rl.installRef, "ralph-loop@official")
    }

    func test_missing_dir_returns_empty() {
        let result = MarketplaceScanner.scan(marketplacesDir: "/nope", installed: [])
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func test_corrupt_manifest_records_warning() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = root.appendingPathComponent("broken/.claude-plugin")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "not json".write(to: dir.appendingPathComponent("marketplace.json"),
                             atomically: true, encoding: .utf8)
        let result = MarketplaceScanner.scan(marketplacesDir: root.path, installed: [])
        XCTAssertTrue(result.nodes.isEmpty)
        XCTAssertFalse(result.warnings.isEmpty)
    }
}
