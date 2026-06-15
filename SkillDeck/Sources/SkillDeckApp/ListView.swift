import SwiftUI
import SkillDeckCore

struct ListView: View {
    let store: AppStore
    let filter: SidebarFilter
    @Binding var selection: String?
    @State private var query: String = ""

    private var rows: [SkillItem] {
        let base: [SkillItem]
        switch filter {
        case .all:        base = store.items
        case .favorites:  base = store.favoriteItems()
        case .recents:    base = store.recentItems(limit: 50)
        case .commands:   base = store.items.filter { $0.kind != .skill }
        case .skills:     base = store.items.filter { $0.kind == .skill }
        case .plugin(let p): base = store.items.filter { $0.pluginName == p }
        case .diagnostics: base = []
        }
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            || ($0.pluginName?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        Group {
            if case .diagnostics = filter {
                DiagnosticsView(store: store)
            } else {
                List(rows, selection: $selection) { item in
                    HStack {
                        Image(systemName: item.kind == .skill ? "sparkles" : "terminal")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.body)
                            Text(item.description).font(.caption)
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if store.isFavorite(item.id) {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                    }
                    .tag(item.id)
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search skills & commands")
    }
}
