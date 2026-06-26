import SwiftUI
import SkillDeckCore

struct SidebarView: View {
    let store: AppStore
    @Binding var filter: SidebarFilter

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
                Label("My Local", systemImage: "folder.badge.person.crop").tag(SidebarFilter.localSkills)
                Label("Built-in", systemImage: "wrench.and.screwdriver").tag(SidebarFilter.builtin)
                Label("Project", systemImage: "folder.badge.gearshape").tag(SidebarFilter.project)
                Label("MCP", systemImage: "network").tag(SidebarFilter.mcp)
                Label("Agents", systemImage: "person.2.fill").tag(SidebarFilter.agents)
            }
            Section("Browse") {
                Label("Marketplace", systemImage: "puzzlepiece.extension").tag(SidebarFilter.marketplace)
            }
            Section {
                Label("Diagnostics", systemImage: "exclamationmark.triangle")
                    .tag(SidebarFilter.diagnostics)
            }
        }
        .listStyle(.sidebar)
    }
}
