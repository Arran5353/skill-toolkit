import XCTest
@testable import SkillDeckCore

final class ArgumentHintParserTests: XCTestCase {
    func test_brand_style() {
        XCTAssertEqual(ArgumentHintParser.subcommands(from: "[update|review|create] [args]"),
                       ["update", "review", "create"])
    }
    func test_impeccable_dotted_groups() {
        let hint = "[craft|shape · audit|critique · init|document|extract|live] [target]"
        XCTAssertEqual(ArgumentHintParser.subcommands(from: hint),
                       ["craft","shape","audit","critique","init","document","extract","live"])
    }
    func test_placeholders_only_returns_empty() {
        XCTAssertEqual(ArgumentHintParser.subcommands(from: "[design-type] [context]"), [])
        XCTAssertEqual(ArgumentHintParser.subcommands(from: "[target]"), [])
    }
    func test_empty_hint() {
        XCTAssertEqual(ArgumentHintParser.subcommands(from: ""), [])
    }
    func test_dedup_preserves_order() {
        XCTAssertEqual(ArgumentHintParser.subcommands(from: "[a|b|a]"), ["a","b"])
    }
}
