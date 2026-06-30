import Foundation

public struct ArgumentPlaceholders {
    public struct Placeholder: Equatable, Sendable {
        public let token: String   // the exact text to replace, e.g. "<url>" or "[target]"
        public let name: String    // display name, e.g. "url" or "target"
        public let required: Bool  // true for <...>, false for [...]

        public init(token: String, name: String, required: Bool) {
            self.token = token
            self.name = name
            self.required = required
        }
    }

    /// Extracts fillable placeholders from an invocation string.
    /// A placeholder is `<name>` (required) or `[name]` (optional). EXCLUDES bracket groups
    /// that are sub-command choice lists (contain '|' or '·') — those are not fillable params.
    public static func placeholders(in text: String) -> [Placeholder] {
        var results: [Placeholder] = []
        var seen: Set<String> = []

        // Match <...> and [...] groups
        let pattern = #"(<[^<>]+>|\[[^\[\]]+\])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            let fullRange = match.range(at: 0)
            let token = nsText.substring(with: fullRange)

            let isAngle = token.hasPrefix("<")
            let inner: String
            if isAngle {
                inner = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            } else {
                // square bracket
                inner = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                // Skip choice lists: contain '|' or '·'
                if inner.contains("|") || inner.contains("·") {
                    continue
                }
            }

            if seen.contains(token) { continue }
            seen.insert(token)

            results.append(Placeholder(token: token, name: inner, required: isAngle))
        }

        return results
    }

    /// Replaces each placeholder token with the user's value (empty values: the token is removed
    /// and surrounding extra whitespace collapsed). Returns the final command string, trimmed.
    public static func fill(_ text: String, values: [String: String]) -> String {
        var result = text

        // Get all placeholders so we know which tokens to replace
        let phs = placeholders(in: text)

        for ph in phs {
            let value = values[ph.name] ?? ""
            result = result.replacingOccurrences(of: ph.token, with: value)
        }

        // Collapse multiple spaces to one and trim
        let components = result.components(separatedBy: .whitespaces)
        result = components.filter { !$0.isEmpty }.joined(separator: " ")

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
