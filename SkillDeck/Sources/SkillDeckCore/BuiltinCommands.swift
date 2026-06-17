import Foundation

public struct BuiltinCommands {
    /// Claude Code's built-in slash commands. Inlined (not a bundled resource) so it works
    /// identically under `swift run` and inside a packaged .app — no Bundle.module lookup,
    /// which is fragile across packaging layouts. Community PRs: edit this list.
    private static let entries: [(name: String, description: String)] = [
        ("clear",  "Clear the conversation history and free up context."),
        ("config", "Open the Claude Code settings/config UI."),
        ("review", "Review a pull request."),
        ("init",   "Initialize a new CLAUDE.md with codebase documentation."),
        ("help",   "Show help and available commands."),
    ]

    public static func load() -> [SkillItem] {
        entries.map { e in
            SkillItem(name: e.name, kind: .builtinCommand, scope: .builtin,
                      pluginName: nil, description: e.description, body: "",
                      filePath: nil,
                      insertText: Injector.defaultInsertText(kind: .builtinCommand, name: e.name))
        }
    }
}
