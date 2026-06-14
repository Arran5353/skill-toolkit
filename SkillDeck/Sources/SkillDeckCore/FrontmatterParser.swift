import Foundation

public struct FrontmatterParser {
    public struct Result: Equatable {
        public let frontmatter: [String: String]
        public let body: String
    }

    /// Parses a `---`-fenced YAML-ish frontmatter block (flat key: value pairs only).
    /// Tolerant: missing/closing fence → empty frontmatter, whole text as body.
    public static func parse(_ text: String) -> Result {
        let lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return Result(frontmatter: [:], body: text)
        }
        // find closing fence
        var closing: Int? = nil
        for i in 1..<lines.count where lines[i].trimmingCharacters(in: .whitespaces) == "---" {
            closing = i; break
        }
        guard let end = closing else {
            return Result(frontmatter: [:], body: text)
        }
        var map: [String: String] = [:]
        for i in 1..<end {
            let line = lines[i]
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { map[key] = value }
        }
        let body = lines[(end + 1)...].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(frontmatter: map, body: body)
    }
}
