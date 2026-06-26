import SwiftUI
import SkillDeckCore

struct MarketplaceView: View {
    let store: AppStore
    @Binding var selection: String?
    let claudeAvailable: Bool
    @State private var query: String = ""
    @State private var collapsed: Set<String> = []

    /// Real marketplaces only (not side-branch roots).
    private var marketplaces: [Node] {
        store.nodes.filter { $0.kind == .marketplace && $0.id.hasPrefix("mp|") }
    }

    private func plugins(for marketplace: Node) -> [Node] {
        var kids = store.children(of: marketplace.id)
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if !q.isEmpty {
            kids = kids.filter {
                $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
            }
        }
        // Installed plugins float to the top so they're not buried below the long
        // list of available ones; alphabetical within each group.
        return kids.sorted { a, b in
            let aInstalled = a.status == .installed
            let bInstalled = b.status == .installed
            if aInstalled != bInstalled { return aInstalled }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(marketplaces) { mp in
                let visiblePlugins = plugins(for: mp)
                if !visiblePlugins.isEmpty {
                    Section {
                        if !collapsed.contains(mp.id) {
                            ForEach(visiblePlugins) { plugin in
                                pluginRow(plugin).tag(plugin.id)
                            }
                        }
                    } header: {
                        marketplaceHeader(mp, count: visiblePlugins.count)
                    }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search plugins")
    }

    // Big, distinct, collapsible marketplace header.
    private func marketplaceHeader(_ mp: Node, count: Int) -> some View {
        let isCollapsed = collapsed.contains(mp.id)
        let accent = NodeTheme.accent(.marketplace)
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                if isCollapsed { collapsed.remove(mp.id) } else { collapsed.insert(mp.id) }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                Image(systemName: "bag.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(accent)
                Text(mp.name)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(count)")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(accent.opacity(0.15), in: Capsule())
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)   // don't uppercase the marketplace name
    }

    private func pluginRow(_ plugin: Node) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(plugin.name).font(.body)
                if !plugin.description.isEmpty {
                    Text(plugin.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            InstallButton(store: store, node: plugin, claudeAvailable: claudeAvailable)
        }
    }
}

// MARK: - InstallButton

struct InstallButton: View {
    let store: AppStore
    let node: Node
    let claudeAvailable: Bool

    private var installState: Installer.State {
        store.installer.states[node.id] ?? .idle
    }

    var body: some View {
        switch node.status {
        case .installed:
            Label("Installed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.caption)
        case .notApplicable:
            EmptyView()
        case .available:
            switch installState {
            case .idle:
                Button("Install") {
                    Task { await store.installer.install(node) }
                }
                .buttonStyle(.bordered)
                .disabled(!claudeAvailable)

            case .installing:
                ProgressView()
                    .controlSize(.small)

            case .succeeded:
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

            case .failed(let msg):
                VStack(alignment: .trailing, spacing: 2) {
                    Button("Retry") {
                        Task { await store.installer.install(node) }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!claudeAvailable)
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                        .frame(maxWidth: 160, alignment: .trailing)
                }
            }
        }
    }
}
