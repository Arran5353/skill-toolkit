import Foundation

public struct RecentEntry: Codable, Equatable, Sendable {
    public var id: String
    public var lastUsed: Double   // epoch seconds
    public var count: Int
    public init(id: String, lastUsed: Double, count: Int) {
        self.id = id; self.lastUsed = lastUsed; self.count = count
    }
}

public struct PersistedState: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var favorites: [String] = []
    public var recents: [RecentEntry] = []
    public var overrides: [String: String] = [:]
    public init() {}
}

public struct Persistence {
    /// Default location: ~/Library/Application Support/SkillDeck/state.json
    public static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SkillDeck/state.json").path
    }

    public static func load(from path: String) throws -> PersistedState {
        guard FileManager.default.fileExists(atPath: path) else { return PersistedState() }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(PersistedState.self, from: data)
    }

    public static func save(_ state: PersistedState, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: url)
    }
}
