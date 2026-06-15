import SwiftUI
import SkillDeckCore

struct ListView: View {
    let store: AppStore
    let filter: SidebarFilter
    @Binding var selection: String?
    @State private var query: String = ""

    private var rows: [Node] {
        let base: [Node]
        switch filter {
        case .all:
            // Not reached: SidebarFilter.all is routed to TreeListView by ContentColumn.
            base = store.nodes.filter { $0.isLeaf }
        case .favorites:
            base = store.favoriteItems()
        case .recents:
            base = store.recentItems(limit: 50)
        case .commands:
            // Only plugin/project commands here; built-in slash commands have their own filter.
            base = store.nodes.filter { $0.kind == .command }
        case .skills:
            // Only plugin/project skills here; user-placed local skills have their own filter.
            base = store.nodes.filter { $0.kind == .skill }
        case .localSkills:
            base = store.nodes.filter { $0.kind == .localSkill }
        case .builtin:
            base = store.nodes.filter { $0.kind == .builtinCommand }
        case .marketplace, .diagnostics:
            base = []
        }
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
