import Foundation

public enum NodeKind: String, Equatable, Sendable {
    case marketplace, plugin, skill, command, builtinCommand, localSkill
}

public enum InstallStatus: Equatable, Sendable {
    case installed, available, notApplicable
}

public struct Node: Identifiable, Equatable, Sendable {
    public let id: String
    public let kind: NodeKind
    public let name: String
    public let description: String
    public let status: InstallStatus
    public let parentID: String?

    // leaf-only
    public let body: String?
    public let insertText: String?
    public let filePath: String?

    // plugin-only
    public let marketplaceName: String?
    public let installRef: String?

    public init(id: String, kind: NodeKind, name: String, description: String,
                status: InstallStatus, parentID: String?,
                body: String? = nil, insertText: String? = nil, filePath: String? = nil,
                marketplaceName: String? = nil, installRef: String? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.description = description
        self.status = status; self.parentID = parentID
        self.body = body; self.insertText = insertText; self.filePath = filePath
        self.marketplaceName = marketplaceName; self.installRef = installRef
    }

    public static func marketplaceID(_ name: String) -> String { "mp|\(name)" }
    public static func pluginID(marketplace: String, plugin: String) -> String {
        "mp|\(marketplace)|plugin|\(plugin)"
    }

    public var isLeaf: Bool {
        switch kind {
        case .skill, .command, .builtinCommand, .localSkill: return true
        case .marketplace, .plugin: return false
        }
    }
}
