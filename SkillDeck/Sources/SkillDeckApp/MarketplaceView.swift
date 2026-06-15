import SwiftUI
import SkillDeckCore

struct MarketplaceView: View {
    let store: AppStore
    @Binding var selection: String?
    let claudeAvailable: Bool
    @State private var query: String = ""

    /// Real marketplaces only (not side-branch roots).
    private var marketplaces: [Node] {
        store.nodes.filter { $0.kind == .marketplace && $0.id.hasPrefix("mp|") }
    }

    private func plugins(for marketplace: Node) -> [Node] {
        let kids = store.children(of: marketplace.id)
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return kids }
        return kids.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(marketplaces) { mp in
                let visiblePlugins = plugins(for: mp)
                if !visiblePlugins.isEmpty {
                    Section(mp.name) {
                        ForEach(visiblePlugins) { plugin in
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
                                InstallButton(
                                    store: store,
                                    node: plugin,
                                    claudeAvailable: claudeAvailable
                                )
                            }
                            .tag(plugin.id)
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search plugins")
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
