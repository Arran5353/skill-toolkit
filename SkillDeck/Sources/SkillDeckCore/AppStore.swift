import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public private(set) var nodes: [Node] = []
    public private(set) var warnings: [ScanWarning] = []
    public private(set) var state: PersistedState
    public let installer = Installer()

    private let statePath: String

    public init(statePath: String = Persistence.defaultPath()) {
        self.statePath = statePath
        do {
            self.state = try Persistence.load(from: statePath)
        } catch {
            NSLog("SkillDeck: failed to load state from \(statePath): \(error). Starting with empty state.")
            self.state = PersistedState()
        }
    }

    // MARK: - Catalog
    public func setNodes(_ nodes: [Node]) { self.nodes = nodes }
    public func setWarnings(_ warnings: [ScanWarning]) { self.warnings = warnings }
    public func node(id: String) -> Node? { nodes.first { $0.id == id } }

    public func children(of parentID: String) -> [Node] {
        nodes.filter { $0.parentID == parentID }
    }

    public func rootNodes() -> [Node] {
        nodes.filter { $0.parentID == nil }
    }

    /// Case-insensitive match over name + description. Empty query = all nodes.
    public func search(_ query: String) -> [Node] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nodes }
        return nodes.filter {
            $0.name.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
        }
    }

    // MARK: - Favorites
    public func isFavorite(_ id: String) -> Bool { state.favorites.contains(id) }
    public func toggleFavorite(_ id: String) {
        guard let n = node(id: id), n.isLeaf else { return }
        if let idx = state.favorites.firstIndex(of: id) { state.favorites.remove(at: idx) }
        else { state.favorites.append(id) }
        persist()
    }
    public func favoriteItems() -> [Node] {
        state.favorites.compactMap { id in nodes.first { $0.id == id } }
    }

    // MARK: - Recents
    public func recordUse(_ id: String, now: Double = Date().timeIntervalSince1970) {
        if let idx = state.recents.firstIndex(where: { $0.id == id }) {
            state.recents[idx].count += 1
            state.recents[idx].lastUsed = now
        } else {
            state.recents.append(RecentEntry(id: id, lastUsed: now, count: 1))
        }
        persist()
    }
    public func useCount(_ id: String) -> Int {
        state.recents.first { $0.id == id }?.count ?? 0
    }
    public func recentItems(limit: Int) -> [Node] {
        state.recents.sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit)
            .compactMap { entry in nodes.first { $0.id == entry.id } }
    }

    // MARK: - Overrides
    public func setOverride(_ id: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { state.overrides[id] = nil } else { state.overrides[id] = text }
        persist()
    }
    public func removeOverride(_ id: String) {
        state.overrides[id] = nil
        persist()
    }
    public func effectiveInsertText(for id: String) -> String {
        if let o = state.overrides[id] { return o }
        return nodes.first { $0.id == id }?.insertText ?? ""
    }

    // MARK: - Private
    private func persist() { try? Persistence.save(state, to: statePath) }
}
