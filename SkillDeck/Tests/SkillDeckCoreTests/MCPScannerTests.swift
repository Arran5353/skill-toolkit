import XCTest
@testable import SkillDeckCore

final class MCPScannerTests: XCTestCase {
    func test_flat_http_server() {
        let s = MCPScanner.parse("{\"github\":{\"type\":\"http\",\"url\":\"https://x/mcp/\"}}")
        XCTAssertEqual(s, [MCPServerInfo(name: "github", transport: "http", endpoint: "https://x/mcp/")])
    }

    func test_mcpServers_wrapper() {
        let s = MCPScanner.parse("{\"mcpServers\":{\"a\":{\"command\":\"node srv.js\"}}}")
        XCTAssertEqual(s, [MCPServerInfo(name: "a", transport: "stdio", endpoint: "node srv.js")])
    }

    func test_multiple_sorted() {
        let s = MCPScanner.parse("{\"z\":{\"type\":\"http\",\"url\":\"u\"},\"a\":{\"type\":\"http\",\"url\":\"v\"}}")
        XCTAssertEqual(s.map(\.name), ["a", "z"])
    }

    func test_malformed_empty() {
        XCTAssertEqual(MCPScanner.parse("not json"), [])
        XCTAssertEqual(MCPScanner.parse("{}"), [])
    }
}
