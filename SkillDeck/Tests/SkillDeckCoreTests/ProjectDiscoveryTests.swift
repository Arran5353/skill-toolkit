import XCTest
@testable import SkillDeckCore

final class ProjectDiscoveryTests: XCTestCase {
    func test_returns_unique_projects_most_recent_first() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.jsonl")
        let content = """
        {"display":"a","timestamp":100,"project":"/p/alpha"}
        {"display":"b","timestamp":300,"project":"/p/beta"}
        {"display":"c","timestamp":200,"project":"/p/alpha"}
        """
        try content.write(to: file, atomically: true, encoding: .utf8)

        let projects = ProjectDiscovery.recentProjects(historyPath: file.path, limit: 10)
        XCTAssertEqual(projects, ["/p/beta", "/p/alpha"]) // beta ts300 > alpha latest ts200
    }

    func test_respects_limit() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.jsonl")
        try "{\"timestamp\":1,\"project\":\"/a\"}\n{\"timestamp\":2,\"project\":\"/b\"}"
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDiscovery.recentProjects(historyPath: file.path, limit: 1), ["/b"])
    }

    func test_missing_file_returns_empty() {
        XCTAssertEqual(ProjectDiscovery.recentProjects(historyPath: "/nope/x.jsonl", limit: 5), [])
    }

    func test_skips_malformed_lines() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.jsonl")
        try "not json\n{\"timestamp\":5,\"project\":\"/good\"}\n{}"
            .write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectDiscovery.recentProjects(historyPath: file.path, limit: 5), ["/good"])
    }
}
