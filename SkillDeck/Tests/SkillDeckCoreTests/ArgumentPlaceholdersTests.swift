import XCTest
@testable import SkillDeckCore

final class ArgumentPlaceholdersTests: XCTestCase {
    func test_angle_required() {
        let p = ArgumentPlaceholders.placeholders(in: "/taste <url>")
        XCTAssertEqual(p, [.init(token: "<url>", name: "url", required: true)])
    }

    func test_square_optional() {
        let p = ArgumentPlaceholders.placeholders(in: "/impeccable polish [target]")
        XCTAssertEqual(p, [.init(token: "[target]", name: "target", required: false)])
    }

    func test_skips_choice_lists() {
        // "[a|b|c]" and dotted groups are sub-commands, not params
        let p = ArgumentPlaceholders.placeholders(in: "/x [update|review|create] [args]")
        XCTAssertEqual(p.map(\.name), ["args"])
    }

    func test_multiple_mixed() {
        let p = ArgumentPlaceholders.placeholders(in: "/cmd <required-arg> [optional-arg]")
        XCTAssertEqual(p.map(\.name), ["required-arg", "optional-arg"])
        XCTAssertEqual(p.map(\.required), [true, false])
    }

    func test_none() {
        XCTAssertTrue(ArgumentPlaceholders.placeholders(in: "/clear").isEmpty)
        XCTAssertTrue(ArgumentPlaceholders.placeholders(in: "use the brainstorming skill").isEmpty)
    }

    func test_fill_substitutes_and_collapses() {
        let out = ArgumentPlaceholders.fill("/taste <url> [target]", values: ["url": "https://x.com"])
        XCTAssertEqual(out, "/taste https://x.com")   // empty [target] removed, no double space
    }

    func test_fill_both() {
        let out = ArgumentPlaceholders.fill("/cmd <a> [b]", values: ["a": "1", "b": "2"])
        XCTAssertEqual(out, "/cmd 1 2")
    }
}
