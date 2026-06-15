import Foundation
import Observation

@MainActor
@Observable
public final class AppStore {
    public private(set) var items: [SkillItem] = []
    public private(set) var warnings: [ScanWarning] = []
    public private(set) var state: PersistedState

    private let statePath: String

    public init(statePath: String = Persistence.defaultPath()) {
        self.statePath = statePath
        self.state = (try? Persistence.load(from: statePath)) ?? PersistedState()
    }

    // MARK: - Catalog
    public func setItems(_ items: [SkillItem]) { self.items = items }
    public func setWarnings(_ warnings: [ScanWarning]) { self.warnings = warnings }
    public func item(id: String) -> SkillItem? { items.first { $0.id == id } }

    /// Case-insensitive match over name + description + plugin name. Empty query = all.
    public func search(_ query: String) -> [SkillItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter {
            $0.name.lowercased().contains(q)
            || $0.description.lowercased().contains(q)
            || ($0.pluginName?.lowercased().contains(q) ?? false)
        }
    }

    // MARK: - Favorites
    public func isFavorite(_ id: String) -> Bool { state.favorites.contains(id) }
    public func toggleFavorite(_ id: String) {
        if let idx = state.favorites.firstIndex(of: id) { state.favorites.remove(at: idx) }
        else { state.favorites.append(id) }
        persist()
    }
    public func favoriteItems() -> [SkillItem] {
        state.favorites.compactMap { id in items.first { $0.id == id } }
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
    public func recentItems(limit: Int) -> [SkillItem] {
        state.recents.sorted { $0.lastUsed > $1.lastUsed }
            .prefix(limit)
            .compactMap { entry in items.first { $0.id == entry.id } }
    }

    // MARK: - Overrides
    public func setOverride(_ id: String, text: String) {
        state.overrides[id] = text
        persist()
    }
    public func effectiveInsertText(for id: String) -> String {
        if let override = state.overrides[id] { return override }
        return items.first { $0.id == id }?.insertText ?? ""
    }

    // MARK: - Private
    private func persist() { try? Persistence.save(state, to: statePath) }
}
