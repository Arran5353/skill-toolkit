import XCTest
@testable import SkillDeckCore

final class FuzzyMatcherTests: XCTestCase {
    func test_no_match_returns_nil() {
        XCTAssertNil(FuzzyMatcher.score("xyz", "brainstorming"))
    }

    func test_subsequence_matches() {
        XCTAssertNotNil(FuzzyMatcher.score("bs", "brainstorming"))   // b...s
        XCTAssertNotNil(FuzzyMatcher.score("brnstrm", "brainstorming"))
    }

    func test_empty_query_matches_all() {
        XCTAssertEqual(FuzzyMatcher.score("", "anything"), 0)
    }

    func test_prefix_beats_midmatch() {
        let pre = FuzzyMatcher.score("code", "code-review")!
        let mid = FuzzyMatcher.score("code", "wxcodey")!
        XCTAssertGreaterThan(pre, mid)
    }

    func test_word_boundary_beats_scattered() {
        // "cr" hitting word-starts of "code-review" beats scattered "cr" in "circle"
        // "code-review": c at start (boundary +15), r at word-boundary after '-' (+15)
        // "circle": c at start (boundary +15), r mid-word (no boundary bonus)
        let wb = FuzzyMatcher.score("cr", "code-review")!   // c(ode-) r(eview)
        let sc = FuzzyMatcher.score("cr", "circle")!        // c at start, r scattered mid
        XCTAssertGreaterThan(wb, sc)
    }

    func test_shorter_candidate_ranks_higher_for_same_match() {
        let short = FuzzyMatcher.score("td", "tdd")!
        let long  = FuzzyMatcher.score("td", "a-very-long-thing-with-t-and-d")!
        XCTAssertGreaterThan(short, long)
    }

    func test_case_insensitive() {
        XCTAssertNotNil(FuzzyMatcher.score("BS", "brainstorming"))
    }
}
