import Foundation

public enum ItemKind: String, Codable, Sendable {
    case skill, command, builtinCommand
}

public enum SourceScope: Equatable, Sendable {
    case user
    case project(String)
    case builtin

    public var key: String {
        switch self {
        case .user: return "user"
        case .builtin: return "builtin"
        case .project(let name): return "project:\(name)"
        }
    }
}

public struct SkillItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let kind: ItemKind
    public let scope: SourceScope
    public let pluginName: String?
    public let description: String
    public let body: String
    public let filePath: String?
    public var insertText: String

    public init(name: String, kind: ItemKind, scope: SourceScope,
                pluginName: String?, description: String, body: String,
                filePath: String?, insertText: String) {
        self.id = SkillItem.makeID(scope: scope, pluginName: pluginName, kind: kind, name: name)
        self.name = name
        self.kind = kind
        self.scope = scope
        self.pluginName = pluginName
        self.description = description
        self.body = body
        self.filePath = filePath
        self.insertText = insertText
    }

    public static func makeID(scope: SourceScope, pluginName: String?,
                              kind: ItemKind, name: String) -> String {
        "\(scope.key)|\(pluginName ?? "_")|\(kind.rawValue)|\(name)"
    }
}
