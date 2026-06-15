import SwiftUI
import AppKit
import SkillDeckCore

@main
struct SkillDeckApp: App {
    @State private var store = AppStore()
    @State private var tracker = FrontmostAppTracker()
    @State private var watcher: FileWatcher?
    @State private var selection: String?
    @State private var sidebarFilter: SidebarFilter = .all
    @State private var claudeAvailable: Bool = false

    var body: some Scene {
        Window("SkillDeck", id: "main") {
            NavigationSplitView {
                SidebarView(store: store, filter: $sidebarFilter)
            } content: {
                ContentColumn(
                    store: store,
                    filter: sidebarFilter,
                    selection: $selection,
                    claudeAvailable: claudeAvailable
                )
            } detail: {
                DetailColumn(
                    store: store,
                    tracker: tracker,
                    selection: $selection,
                    claudeAvailable: claudeAvailable
                )
            }
            .frame(minWidth: 820, minHeight: 480)
            .onAppear { bootstrap() }
        }

        MenuBarExtra("SkillDeck", systemImage: "command.square") {
            MenuBarView(store: store, tracker: tracker)
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor
    private func bootstrap() {
        claudeAvailable = Installer.isClaudeAvailable
        tracker.start()
        reload()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let newWatcher = FileWatcher(
            paths: ["\(home)/.claude/skills", "\(home)/.claude/plugins"],
            onChange: { Task { @MainActor in reload() } })
        newWatcher.start()
        self.watcher = newWatcher
    }

    @MainActor
    private func reload() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projects = ProjectDiscovery.recentProjects(
            historyPath: "\(home)/.claude/history.jsonl", limit: 15)
        let result = CatalogLoader.loadDefault(projectDirs: projects)
        store.setNodes(result.nodes)
        store.setWarnings(result.warnings)
    }
}

enum SidebarFilter: Hashable {
    case all, favorites, recents, commands, skills, localSkills, builtin, marketplace, diagnostics
}

// MARK: - Content Column

struct ContentColumn: View {
    let store: AppStore
    let filter: SidebarFilter
    @Binding var selection: String?
    let claudeAvailable: Bool

    var body: some View {
        switch filter {
        case .marketplace:
            MarketplaceView(store: store, selection: $selection, claudeAvailable: claudeAvailable)
        case .diagnostics:
            DiagnosticsView(store: store)
        case .all:
            TreeListView(store: store, selection: $selection)
        default:
            ListView(store: store, filter: filter, selection: $selection)
        }
    }
}

// MARK: - Detail Column

struct DetailColumn: View {
    let store: AppStore
    let tracker: FrontmostAppTracker
    @Binding var selection: String?
    let claudeAvailable: Bool

    var body: some View {
        if let id = selection, let node = store.node(id: id) {
            switch node.kind {
            case .plugin:
                PluginDetailView(store: store, node: node, claudeAvailable: claudeAvailable)
            case .marketplace:
                GroupPlaceholder(name: node.name, subtitle: "Marketplace")
            case .skill, .command, .builtinCommand, .localSkill:
                DetailView(store: store, tracker: tracker, selection: $selection)
            }
        } else {
            ContentUnavailableView(
                "Select an item",
                systemImage: "sidebar.left",
                description: Text("Pick a skill or command to see its usage and inject it."))
        }
    }
}

struct GroupPlaceholder: View {
    let name: String
    let subtitle: String
    var body: some View {
        ContentUnavailableView(
            name,
            systemImage: "folder",
            description: Text(subtitle))
    }
}
