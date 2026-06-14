import Foundation

public struct BuiltinCommands {
    private struct Entry: Decodable { let name: String; let description: String }

    /// Loads built-in commands bundled with the SkillDeckCore module.
    public static func load() -> [SkillItem] {
        guard let url = Bundle.module.url(forResource: "builtin-commands", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return entries.map { e in
            SkillItem(name: e.name, kind: .builtinCommand, scope: .builtin,
                      pluginName: nil, description: e.description, body: "",
                      filePath: nil,
                      insertText: Injector.defaultInsertText(kind: .builtinCommand, name: e.name))
        }
    }
}
