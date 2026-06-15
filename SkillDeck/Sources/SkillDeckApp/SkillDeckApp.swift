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

    var body: some Scene {
        Window("SkillDeck", id: "main") {
            NavigationSplitView {
                SidebarView(store: store, filter: $sidebarFilter)
            } content: {
                ListView(store: store, filter: sidebarFilter, selection: $selection)
            } detail: {
                DetailView(store: store, tracker: tracker, selection: $selection)
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
        tracker.start()
        reload()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let watcher = FileWatcher(
            paths: ["\(home)/.claude/skills", "\(home)/.claude/plugins"],
            onChange: { Task { @MainActor in reload() } })
        watcher.start()
        self.watcher = watcher
    }

    @MainActor
    private func reload() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projects = ProjectDiscovery.recentProjects(
            historyPath: "\(home)/.claude/history.jsonl", limit: 15)
        let result = Scanner.scanDefault(projectDirs: projects)
        store.setItems(result.items)
        store.setWarnings(result.warnings)
    }
}

enum SidebarFilter: Hashable {
    case all, favorites, recents, commands, skills, plugin(String), diagnostics
}
