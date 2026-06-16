import Foundation

public struct ArgumentHintParser {
    /// Extracts sub-command names from an `argument-hint` value.
    /// Only `[...]` groups containing `|` are treated as sub-commands; a group is split on
    /// both `|` and `·`, each token trimmed, empties dropped. Placeholder groups (no `|`) and
    /// free text are ignored. Order preserved, de-duplicated.
    public static func subcommands(from hint: String) -> [String] {
        guard !hint.isEmpty else { return [] }

        var result: [String] = []
        var seen = Set<String>()

        // Extract all [...] groups
        var search = hint[...]
        while let openIdx = search.firstIndex(of: "[") {
            let afterOpen = search.index(after: openIdx)
            guard afterOpen < search.endIndex,
                  let closeIdx = search[afterOpen...].firstIndex(of: "]") else {
                break
            }
            let inner = String(search[afterOpen..<closeIdx])

            // Only process groups that contain "|"
            if inner.contains("|") {
                // Split on both "|" and "·" (middle dot, U+00B7)
                let separators = CharacterSet(charactersIn: "|·")
                let tokens = inner.components(separatedBy: separators)
                for token in tokens {
                    let trimmed = token.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty && seen.insert(trimmed).inserted {
                        result.append(trimmed)
                    }
                }
            }

            search = search[search.index(after: closeIdx)...]
        }

        return result
    }
}
