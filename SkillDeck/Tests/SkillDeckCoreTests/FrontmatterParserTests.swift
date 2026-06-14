import XCTest
@testable import SkillDeckCore

final class FrontmatterParserTests: XCTestCase {
    func test_parses_name_and_description_and_body() {
        let text = """
        ---
        name: brainstorming
        description: Use this before any creative work.
        ---

        # Brainstorming

        Body line.
        """
        let r = FrontmatterParser.parse(text)
        XCTAssertEqual(r.frontmatter["name"], "brainstorming")
        XCTAssertEqual(r.frontmatter["description"], "Use this before any creative work.")
        XCTAssertTrue(r.body.contains("# Brainstorming"))
        XCTAssertFalse(r.body.contains("name:"))
    }

    func test_no_frontmatter_returns_empty_map_and_full_body() {
        let r = FrontmatterParser.parse("Just a body, no fence.")
        XCTAssertTrue(r.frontmatter.isEmpty)
        XCTAssertEqual(r.body, "Just a body, no fence.")
    }

    func test_malformed_frontmatter_does_not_crash() {
        let r = FrontmatterParser.parse("---\nthis is : : broken\n")  // no closing fence
        XCTAssertTrue(r.frontmatter.isEmpty)
        XCTAssertTrue(r.body.contains("broken"))
    }

    func test_empty_string() {
        let r = FrontmatterParser.parse("")
        XCTAssertTrue(r.frontmatter.isEmpty)
        XCTAssertEqual(r.body, "")
    }

    func test_value_with_colon_is_preserved() {
        let text = "---\ndescription: a: b: c\n---\nbody"
        let r = FrontmatterParser.parse(text)
        XCTAssertEqual(r.frontmatter["description"], "a: b: c")
    }
}
