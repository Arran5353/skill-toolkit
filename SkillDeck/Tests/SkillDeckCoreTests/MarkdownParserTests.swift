import XCTest
@testable import SkillDeckCore

final class MarkdownParserTests: XCTestCase {
    func test_fenced_code_with_language() {
        let blocks = MarkdownParser.parse("```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks, [.code("let x = 1", language: "swift")])
    }
    func test_tilde_fence() {
        let blocks = MarkdownParser.parse("~~~\ncode\n~~~")
        XCTAssertEqual(blocks, [.code("code", language: nil)])
    }
    func test_unclosed_fence_emits_code_not_swallow_crash() {
        let blocks = MarkdownParser.parse("```\nline1\nline2")
        XCTAssertEqual(blocks, [.code("line1\nline2", language: nil)])
    }
    func test_plain_prose_is_not_code() {
        let blocks = MarkdownParser.parse("This is a normal sentence.\n\nAnother paragraph.")
        XCTAssertEqual(blocks, [.paragraph("This is a normal sentence."),
                                .paragraph("Another paragraph.")])
    }
    func test_indented_code_block() {
        let src = "intro\n\n    let a = 1\n    let b = 2\n\noutro"
        let blocks = MarkdownParser.parse(src)
        XCTAssertEqual(blocks, [.paragraph("intro"),
                                .code("let a = 1\nlet b = 2", language: nil),
                                .paragraph("outro")])
    }
    func test_heading_and_bullets_preserved() {
        let blocks = MarkdownParser.parse("# Title\n\n- one\n- two")
        XCTAssertEqual(blocks, [.heading(level: 1, text: "Title"),
                                .bullet(text: "one", depth: 0),
                                .bullet(text: "two", depth: 0)])
    }
    func test_fence_closes_only_on_same_marker() {
        // a ~~~ inside a ``` block is content, not a closer
        let blocks = MarkdownParser.parse("```\na\n~~~\nb\n```")
        XCTAssertEqual(blocks, [.code("a\n~~~\nb", language: nil)])
    }
    func test_numbered_and_quote() {
        let blocks = MarkdownParser.parse("1. first\n\n> a quote")
        XCTAssertEqual(blocks, [.numbered(1, "first"), .quote("a quote")])
    }
}
