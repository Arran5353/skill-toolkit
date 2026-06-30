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
    @State private var updateAvailable: UpdateChecker.Release?
    @State private var paletteOpen = false
    @State private var hotKey: GlobalHotKey?

    var body: some Scene {
        Window("SkillDeck", id: "main") {
            ZStack {
                NavigationSplitView {
                    SidebarView(store: store, filter: $sidebarFilter)
                        .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
                } content: {
                    ContentColumn(
                        store: store,
                        filter: sidebarFilter,
                        selection: $selection,
                        claudeAvailable: claudeAvailable,
                        onOpenSearch: { paletteOpen = true }
                    )
                    .navigationSplitViewColumnWidth(min: 260, ideal: 340, max: 620)
                } detail: {
                    DetailColumn(
                        store: store,
                        tracker: tracker,
                        selection: $selection,
                        claudeAvailable: claudeAvailable
                    )
                }

                if paletteOpen {
                    CommandPalette(store: store, tracker: tracker) {
                        paletteOpen = false
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Hidden button to capture ⌘K globally within the window
                Button("") { paletteOpen.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .allowsHitTesting(false)
            }
            .animation(.easeInOut(duration: 0.15), value: paletteOpen)
            .frame(minWidth: 820, minHeight: 480)
            .frame(idealWidth: 1180, idealHeight: 760)
            .onAppear { bootstrap() }
        }

        MenuBarExtra("SkillDeck", systemImage: "command.square") {
            MenuBarView(store: store, tracker: tracker,
                        updateAvailable: updateAvailable,
                        onCheckForUpdates: { checkForUpdates(silent: false) })
        }
        .menuBarExtraStyle(.menu)
    }

    @MainActor
    private func bootstrap() {
        claudeAvailable = Installer.isClaudeAvailable
        tracker.start()
        reload()
        checkForUpdates(silent: true)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let newWatcher = FileWatcher(
            paths: ["\(home)/.claude/skills", "\(home)/.claude/plugins"],
            onChange: { Task { @MainActor in reload() } })
        newWatcher.start()
        self.watcher = newWatcher

        // Register global ⌥⌘K hotkey — brings SkillDeck to front and opens command palette
        let hk = GlobalHotKey { [self] in
            Task { @MainActor in
                NSApplication.shared.activate(ignoringOtherApps: true)
                for w in NSApplication.shared.windows where w.canBecomeMain {
                    w.makeKeyAndOrderFront(nil)
                }
                self.paletteOpen = true
            }
        }
        hk.register()
        self.hotKey = hk
    }

    @MainActor
    private func reload() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        Task {
            let result = await Self.scan(home: home)
            store.setNodes(result.nodes)
            store.setWarnings(result.warnings)
        }
    }

    @MainActor private func checkForUpdates(silent: Bool) {
        let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? UpdateChecker.fallbackVersion
        Task {
            if let rel = await UpdateChecker.checkForUpdate(current: current) {
                updateAvailable = rel
            } else if !silent {
                updateAvailable = nil
            }
        }
    }

    nonisolated private static func scan(home: String) async -> CatalogLoader.Result {
        let projects = ProjectDiscovery.recentProjects(
            historyPath: "\(home)/.claude/history.jsonl", limit: 15)
        return CatalogLoader.loadDefault(projectDirs: projects)
    }
}

enum SidebarFilter: Hashable {
    case all, favorites, recents, commands, skills, localSkills, builtin, project, mcp, agents, marketplace, diagnostics
}

// MARK: - Content Column

struct ContentColumn: View {
    let store: AppStore
    let filter: SidebarFilter
    @Binding var selection: String?
    let claudeAvailable: Bool
    var onOpenSearch: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let onOpenSearch {
                SearchLaunchButton(action: onOpenSearch)
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 6)
            }
            switch filter {
            case .marketplace:
                MarketplaceView(store: store, selection: $selection, claudeAvailable: claudeAvailable)
            case .diagnostics:
                DiagnosticsView(store: store)
            case .all:
                TreeListView(store: store, selection: $selection)
            case .skills:
                TreeListView(store: store, selection: $selection,
                             leafKinds: [.skill, .localSkill])
            case .commands:
                TreeListView(store: store, selection: $selection,
                             leafKinds: [.command, .builtinCommand])
            case .localSkills:
                TreeListView(store: store, selection: $selection,
                             leafKinds: [.localSkill])
            case .builtin:
                TreeListView(store: store, selection: $selection,
                             leafKinds: [.builtinCommand])
            case .project:
                TreeListView(store: store, selection: $selection,
                             rootFilter: { $0.id == TreeBuilder.projectRootID })
            case .mcp:
                TreeListView(store: store, selection: $selection,
                             leafKinds: [.mcpServer])
            case .agents:
                TreeListView(store: store, selection: $selection,
                             leafKinds: [.agent])
            default:
                ListView(store: store, filter: filter, selection: $selection)
            }
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
                GroupPlaceholder(name: node.name,
                                 subtitle: node.id.hasPrefix("mp|") ? "Marketplace" : "")
            case .mcpServer:
                MCPDetailView(node: node)
            case .agent:
                AgentDetailView(node: node)
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

// MARK: - Search Launch Button

/// A toolbar button styled as a search field. Clicking it opens the CommandPalette overlay.
struct SearchLaunchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Search skills & commands…")
                    .font(.system(size: 13))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                Text("⌘K")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 300)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
