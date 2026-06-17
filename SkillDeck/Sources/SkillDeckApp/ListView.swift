import SwiftUI
import SkillDeckCore

/// Flat list used only for the cross-cutting Favorites and Recents filters.
/// All kind/scope filters are rendered hierarchically by TreeListView (see ContentColumn).
struct ListView: View {
    let store: AppStore
    let filter: SidebarFilter
    @Binding var selection: String?
    @State private var query: String = ""

    private var rows: [Node] {
        let base = filter == .recents ? store.recentItems(limit: 50) : store.favoriteItems()
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        List(rows, id: \.id, selection: $selection) { node in
            NodeRow(node: node, isFavorite: node.isLeaf && store.isFavorite(node.id))
                .tag(node.id)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search skills & commands")
    }
}
