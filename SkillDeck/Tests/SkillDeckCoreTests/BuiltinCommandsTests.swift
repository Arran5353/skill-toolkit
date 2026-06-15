import XCTest
@testable import SkillDeckCore

final class BuiltinCommandsTests: XCTestCase {
    func test_loads_builtins_from_bundle_as_skill_items() {
        let items = BuiltinCommands.load()
        XCTAssertFalse(items.isEmpty)
        let clear = items.first { $0.name == "clear" }
        XCTAssertNotNil(clear)
        XCTAssertEqual(clear?.kind, .builtinCommand)
        XCTAssertEqual(clear?.scope, .builtin)
        XCTAssertEqual(clear?.insertText, "/clear")
        XCTAssertNil(clear?.filePath)
    }
}
