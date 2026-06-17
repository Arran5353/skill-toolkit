import SwiftUI
import SkillDeckCore

struct PluginDetailView: View {
    let store: AppStore
    let node: Node
    let claudeAvailable: Bool

    var body: some View {
        let accent = NodeTheme.accent(node.kind)
        let installed = node.status == .installed
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Hero header
                HStack(alignment: .top, spacing: 14) {
                    NodeIconTile(kind: node.kind)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(node.name)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            KindBadge(kind: node.kind)
                            statusPill(installed: installed)
                            if let mp = node.marketplaceName {
                                Label(mp, systemImage: "bag")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Spacer()
                }

                if !node.description.isEmpty {
                    SectionCard(title: "About", systemImage: "info.circle.fill", accent: accent) {
                        Text(node.description)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if installed {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        Text("Installed — its skills and commands appear in the tree.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    SectionCard(title: "Install", systemImage: "arrow.down.circle.fill", accent: accent) {
                        InstallButton(store: store, node: node, claudeAvailable: claudeAvailable)
                        if !claudeAvailable {
                            Label("claude CLI not found — install claude to enable plugin installation.",
                                  systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accentBackdrop(accent)
    }

    private func statusPill(installed: Bool) -> some View {
        let c: Color = installed ? .green : .secondary
        return Label(installed ? "Installed" : "Available",
                     systemImage: installed ? "checkmark.circle.fill" : "circle.dashed")
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(c)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(c.opacity(0.14), in: Capsule())
    }
}
