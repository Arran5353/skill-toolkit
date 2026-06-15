import XCTest
@testable import SkillDeckCore

final class NodeTests: XCTestCase {
    func test_id_helpers() {
        XCTAssertEqual(Node.marketplaceID("official"), "mp|official")
        XCTAssertEqual(Node.pluginID(marketplace: "official", plugin: "ralph-loop"),
                       "mp|official|plugin|ralph-loop")
    }

    func test_isLeaf() {
        func n(_ k: NodeKind) -> Node {
            Node(id: "x", kind: k, name: "n", description: "", status: .notApplicable, parentID: nil)
        }
        XCTAssertTrue(n(.skill).isLeaf)
        XCTAssertTrue(n(.command).isLeaf)
        XCTAssertTrue(n(.builtinCommand).isLeaf)
        XCTAssertTrue(n(.localSkill).isLeaf)
        XCTAssertFalse(n(.plugin).isLeaf)
        XCTAssertFalse(n(.marketplace).isLeaf)
    }
}
