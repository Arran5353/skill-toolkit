import Foundation

public struct Injector {
    /// Derives the default text to insert for an item.
    public static func defaultInsertText(kind: ItemKind, name: String) -> String {
        switch kind {
        case .command, .builtinCommand:
            return name.hasPrefix("/") ? name : "/\(name)"
        case .skill:
            return "use the \(name) skill"
        }
    }
}
