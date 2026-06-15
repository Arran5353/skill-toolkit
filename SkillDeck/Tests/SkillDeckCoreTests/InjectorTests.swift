import XCTest
@testable import SkillDeckCore

final class InjectorTests: XCTestCase {
    func test_command_inserts_slash_name() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .command, name: "code-review"), "/code-review")
    }
    func test_builtin_inserts_slash_name() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .builtinCommand, name: "clear"), "/clear")
    }
    func test_skill_inserts_natural_language_hint() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .skill, name: "brainstorming"),
                       "use the brainstorming skill")
    }
    func test_already_slashed_command_not_double_slashed() {
        XCTAssertEqual(Injector.defaultInsertText(kind: .command, name: "/deploy"), "/deploy")
    }
}
