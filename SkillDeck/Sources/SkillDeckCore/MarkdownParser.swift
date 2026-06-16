/// Public block model and parser for Markdown used by SkillDeck.
///
/// Supports: headings, bullet/numbered lists, blockquotes, paragraphs,
/// fenced code blocks (``` and ~~~), and indented code blocks (≥4 spaces or tab).
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case bullet(text: String, depth: Int)
    case numbered(Int, String)
    case quote(String)
    case paragraph(String)
    case code(String, language: String?)
    case table(header: [String], rows: [[String]])
}

public struct MarkdownParser {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let rawLines = source.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []

        // ── State ────────────────────────────────────────────────────────────
        var inFence = false
        var fenceMarker: Character = "`"   // ` or ~
        var fenceMinLen = 3                 // minimum length of the opening fence
        var fenceLang: String? = nil
        var fenceLines: [String] = []

        // Paragraph accumulator
        var paragraphLines: [String] = []
        // Track whether the previous non-blank block was a list item
        var lastBlockWasList = false

        func flushParagraph() {
            let joined = paragraphLines
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty {
                blocks.append(.paragraph(joined))
            }
            paragraphLines.removeAll()
        }

        func flushFence() {
            let content = fenceLines.joined(separator: "\n")
            blocks.append(.code(content, language: fenceLang))
            fenceLines.removeAll()
            fenceLang = nil
        }

        // ── Helpers ──────────────────────────────────────────────────────────

        /// Returns (level, text) if the trimmed line is an ATX heading.
        func heading(_ line: String) -> (Int, String)? {
            guard line.hasPrefix("#") else { return nil }
            var level = 0
            var idx = line.startIndex
            while idx < line.endIndex, line[idx] == "#", level < 6 {
                level += 1
                idx = line.index(after: idx)
            }
            let text = String(line[idx...]).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : (level, text)
        }

        /// Returns the quote content if the trimmed line is a blockquote.
        func quoteText(_ line: String) -> String? {
            guard line.hasPrefix(">") else { return nil }
            return String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        /// Returns (number, text) if the trimmed line is a numbered list item.
        func numberedText(_ line: String) -> (Int, String)? {
            var digits = ""
            var idx = line.startIndex
            while idx < line.endIndex, line[idx].isNumber {
                digits.append(line[idx])
                idx = line.index(after: idx)
            }
            guard !digits.isEmpty,
                  idx < line.endIndex,
                  line[idx] == "." || line[idx] == ")" else { return nil }
            let rest = String(line[line.index(after: idx)...])
                .trimmingCharacters(in: .whitespaces)
            guard !rest.isEmpty, let n = Int(digits) else { return nil }
            return (n, rest)
        }

        /// Returns (text, depth) if the raw line is a bullet list item.
        func bulletText(_ rawLine: String) -> (String, Int)? {
            let leading = rawLine.prefix { $0 == " " || $0 == "\t" }
            let depth = min(
                leading.filter { $0 == " " }.count / 2 +
                leading.filter { $0 == "\t" }.count,
                3
            )
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
                return (
                    String(trimmed.dropFirst(marker.count))
                        .trimmingCharacters(in: .whitespaces),
                    depth
                )
            }
            return nil
        }

        /// Returns true if the line qualifies as an indented code line (≥4 spaces or leading tab).
        func isIndentedCode(_ raw: String) -> Bool {
            if raw.hasPrefix("\t") { return true }
            return raw.hasPrefix("    ")   // 4 spaces
        }

        /// Strips the 4-space / tab indent from an indented code line.
        func stripIndent(_ raw: String) -> String {
            if raw.hasPrefix("\t") { return String(raw.dropFirst()) }
            if raw.hasPrefix("    ") { return String(raw.dropFirst(4)) }
            return raw
        }

        /// Splits a pipe-table row into trimmed cells.
        /// Handles optional leading/trailing pipes.
        func splitTableRow(_ line: String) -> [String] {
            var s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("|") { s = String(s.dropFirst()) }
            if s.hasSuffix("|") { s = String(s.dropLast()) }
            return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        }

        /// Returns true if the trimmed line is a GFM separator row (cells are dashes ± colons).
        func isSeparatorRow(_ line: String) -> Bool {
            let cells = splitTableRow(line)
            guard !cells.isEmpty else { return false }
            for cell in cells {
                // Cell must contain at least one dash and only dashes and colons
                guard cell.contains("-"),
                      cell.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) else { return false }
            }
            return true
        }

        /// Returns true if the trimmed line looks like a table row (contains `|`).
        func isTableRow(_ line: String) -> Bool {
            return line.contains("|")
        }

        /// Returns true if the trimmed line opens a fence (``` or ~~~) of ≥3 marker chars.
        func opensFence(_ trimmed: String) -> (Character, Int, String?)? {
            for ch: Character in ["`", "~"] {
                guard trimmed.first == ch else { continue }
                let run = trimmed.prefix(while: { $0 == ch })
                if run.count >= 3 {
                    let rest = String(trimmed.dropFirst(run.count))
                        .trimmingCharacters(in: .whitespaces)
                    let lang: String? = rest.isEmpty ? nil : rest
                    return (ch, run.count, lang)
                }
            }
            return nil
        }

        /// Returns true if the trimmed line closes a fence opened with `marker`/`minLen`.
        func closesFence(_ trimmed: String, marker: Character, minLen: Int) -> Bool {
            guard trimmed.first == marker else { return false }
            let run = trimmed.prefix(while: { $0 == marker })
            return run.count >= minLen && run.count == trimmed.count
        }

        // ── Main pass ────────────────────────────────────────────────────────
        var i = 0
        while i < rawLines.count {
            let rawLine = rawLines[i]
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            // ── Inside a fenced code block ───────────────────────────────────
            if inFence {
                if closesFence(trimmed, marker: fenceMarker, minLen: fenceMinLen) {
                    flushFence()
                    inFence = false
                    lastBlockWasList = false
                } else {
                    fenceLines.append(rawLine)
                }
                i += 1
                continue
            }

            // ── Fence open? ──────────────────────────────────────────────────
            if let (marker, len, lang) = opensFence(trimmed) {
                flushParagraph()
                inFence = true
                fenceMarker = marker
                fenceMinLen = len
                fenceLang = lang
                lastBlockWasList = false
                i += 1
                continue
            }

            // ── Blank line ───────────────────────────────────────────────────
            if trimmed.isEmpty {
                flushParagraph()
                // Don't reset lastBlockWasList here — we need it to survive a
                // blank line so indented code right after a list isn't confused.
                // (We reset it once we've emitted a non-list, non-blank block.)
                i += 1
                continue
            }

            // ── ATX heading ──────────────────────────────────────────────────
            if let (level, text) = heading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: level, text: text))
                lastBlockWasList = false
                i += 1
                continue
            }

            // ── Blockquote ───────────────────────────────────────────────────
            if let q = quoteText(trimmed) {
                flushParagraph()
                blocks.append(.quote(q))
                lastBlockWasList = false
                i += 1
                continue
            }

            // ── Numbered list ────────────────────────────────────────────────
            if let (n, text) = numberedText(trimmed) {
                flushParagraph()
                blocks.append(.numbered(n, text))
                lastBlockWasList = true
                i += 1
                continue
            }

            // ── Bullet list ──────────────────────────────────────────────────
            if let (text, depth) = bulletText(rawLine) {
                flushParagraph()
                blocks.append(.bullet(text: text, depth: depth))
                lastBlockWasList = true
                i += 1
                continue
            }

            // ── Indented code block ──────────────────────────────────────────
            // Only when we're NOT immediately continuing a list item and the
            // current line is indented ≥4 spaces / tab.
            if isIndentedCode(rawLine) && !lastBlockWasList && paragraphLines.isEmpty {
                // Collect consecutive indented lines (blank lines between them
                // count as separators — stop on the first blank).
                var codeContent: [String] = []
                while i < rawLines.count {
                    let rl = rawLines[i]
                    let tr = rl.trimmingCharacters(in: .whitespaces)
                    if tr.isEmpty { break }
                    if isIndentedCode(rl) {
                        codeContent.append(stripIndent(rl))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.code(codeContent.joined(separator: "\n"), language: nil))
                lastBlockWasList = false
                // Don't increment i — the outer loop will handle the next line
                continue
            }

            // ── GFM pipe table ───────────────────────────────────────────────
            // Only try when not in a fence, current line has a pipe, and the
            // very next line is a valid separator row.
            if isTableRow(trimmed) && (i + 1) < rawLines.count {
                let nextTrimmed = rawLines[i + 1].trimmingCharacters(in: .whitespaces)
                if isSeparatorRow(nextTrimmed) {
                    flushParagraph()
                    let header = splitTableRow(trimmed)
                    // Skip header line and separator line
                    i += 2
                    var dataRows: [[String]] = []
                    while i < rawLines.count {
                        let rowTrimmed = rawLines[i].trimmingCharacters(in: .whitespaces)
                        if rowTrimmed.isEmpty || !isTableRow(rowTrimmed) { break }
                        dataRows.append(splitTableRow(rowTrimmed))
                        i += 1
                    }
                    blocks.append(.table(header: header, rows: dataRows))
                    lastBlockWasList = false
                    continue
                }
            }

            // ── Paragraph ────────────────────────────────────────────────────
            paragraphLines.append(trimmed)
            lastBlockWasList = false
            i += 1
        }

        // ── Flush any open state at EOF ──────────────────────────────────────
        if inFence {
            // Unclosed fence: still emit collected lines as a code block
            flushFence()
        } else {
            flushParagraph()
        }

        return blocks
    }
}
