import Foundation

/// A simple, deterministic fuzzy matcher using subsequence matching + weighted scoring.
public struct FuzzyMatcher {
    /// Returns a relevance score if `query` fuzzy-matches `candidate` (case-insensitive
    /// subsequence), or nil if no match. Higher = better. Empty query returns 0 (matches all).
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = query.lowercased()
        let c = candidate.lowercased()

        // Empty query always matches with score 0
        guard !q.isEmpty else { return 0 }

        // Collect matched positions via subsequence walk
        let qChars = Array(q)
        let cChars = Array(c)
        var matchedPositions: [Int] = []

        var qi = 0
        for (ci, ch) in cChars.enumerated() {
            if qi < qChars.count && ch == qChars[qi] {
                matchedPositions.append(ci)
                qi += 1
            }
        }

        // Not all query chars matched → no match
        guard matchedPositions.count == qChars.count else { return nil }

        var score = 0

        // +100 if candidate starts with the query (prefix match)
        if c.hasPrefix(q) {
            score += 100
        }

        // Separator set for word-boundary detection
        let separators: Set<Character> = [" ", "-", "_", "/", "."]

        // Per-matched-position bonuses
        var prevMatchedPos: Int? = nil
        for (i, pos) in matchedPositions.enumerated() {
            // Word boundary bonus
            let isWordBoundary: Bool
            if pos == 0 {
                isWordBoundary = true
            } else {
                let prevChar = cChars[pos - 1]
                // separator before current char
                if separators.contains(prevChar) {
                    isWordBoundary = true
                } else {
                    // camelCase: prev is lowercase, current is uppercase (in original candidate)
                    let origChars = Array(candidate)
                    let origPrev = origChars[pos - 1]
                    let origCurr = origChars[pos]
                    isWordBoundary = origPrev.isLowercase && origCurr.isUppercase
                }
            }
            if isWordBoundary {
                score += 15
            }

            // Consecutive streak bonus
            if let prev = prevMatchedPos, pos == prev + 1 {
                score += 10
            }

            // Gap penalty: chars skipped between matches
            let gapStart = (i == 0) ? 0 : (prevMatchedPos! + 1)
            let gap = pos - gapStart
            score -= gap

            prevMatchedPos = pos
        }

        // Shorter candidate bonus
        score += (50 - min(cChars.count, 50))

        return score
    }
}
