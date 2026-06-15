import SwiftUI
import SkillDeckCore

struct SidebarView: View {
    let store: AppStore
    @Binding var filter: SidebarFilter

    private var plugins: [String] {
        Array(Set(store.items.compactMap { $0.pluginName })).sorted()
    }

    var body: some View {
        List(selection: Binding(
            get: { filter },
            set: { if let v = $0 { filter = v } })) {
            Section {
                Label("Favorites", systemImage: "star").tag(SidebarFilter.favorites)
                Label("Recent", systemImage: "clock").tag(SidebarFilter.recents)
                Label("All", systemImage: "square.grid.2x2").tag(SidebarFilter.all)
            }
            Section("Type") {
                Label("Commands", systemImage: "terminal").tag(SidebarFilter.commands)
                Label("Skills", systemImage: "sparkles").tag(SidebarFilter.skills)
            }
            Section("Plugins") {
                ForEach(plugins, id: \.self) { p in
                    Label(p, systemImage: "puzzlepiece").tag(SidebarFilter.plugin(p))
                }
            }
            Section {
                Label("Diagnostics", systemImage: "exclamationmark.triangle")
                    .tag(SidebarFilter.diagnostics)
            }
        }
        .listStyle(.sidebar)
    }
}
