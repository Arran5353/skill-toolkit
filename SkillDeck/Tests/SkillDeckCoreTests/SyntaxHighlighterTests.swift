import XCTest
@testable import SkillDeckCore

final class SyntaxHighlighterTests: XCTestCase {
    private func reassemble(_ toks: [SyntaxToken]) -> String { toks.map(\.text).joined() }

    func test_lossless_roundtrip() {
        let code = "let x = 42 // hi\nfunc f() { return \"s\" }"
        let toks = SyntaxHighlighter.tokenize(code, language: "swift")
        XCTAssertEqual(reassemble(toks), code)
    }

    func test_keyword_detected() {
        let toks = SyntaxHighlighter.tokenize("func", language: "swift")
        XCTAssertTrue(toks.contains { $0.text == "func" && $0.kind == .keyword })
    }

    func test_string_detected() {
        let toks = SyntaxHighlighter.tokenize("\"hello\"", language: "swift")
        XCTAssertTrue(toks.contains { $0.text == "\"hello\"" && $0.kind == .string })
    }

    func test_comment_detected() {
        let toks = SyntaxHighlighter.tokenize("x // note", language: "swift")
        XCTAssertTrue(toks.contains { $0.text.contains("// note") && $0.kind == .comment })
    }

    func test_number_detected() {
        let toks = SyntaxHighlighter.tokenize("3.14", language: "swift")
        XCTAssertTrue(toks.contains { $0.text == "3.14" && $0.kind == .number })
    }

    func test_hash_comment_for_bash() {
        let toks = SyntaxHighlighter.tokenize("echo hi # comment", language: "bash")
        XCTAssertTrue(toks.contains { $0.text.contains("# comment") && $0.kind == .comment })
    }

    func test_unknown_language_still_lossless() {
        let code = "random text 123 \"q\""
        let toks = SyntaxHighlighter.tokenize(code, language: nil)
        XCTAssertEqual(reassemble(toks), code)
    }
}
