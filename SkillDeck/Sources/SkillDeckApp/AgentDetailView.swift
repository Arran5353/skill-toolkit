import SwiftUI
import SkillDeckCore

/// Read-only detail card for an agent node.
/// Shows the agent name, description and (optionally) model — no inject/copy buttons.
struct AgentDetailView: View {
    let node: Node

    var body: some View {
        let accent = NodeTheme.accent(node.kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(accent: accent)
                aboutCard(accent: accent)
                noteCard(accent: accent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accentBackdrop(accent)
    }

    // MARK: - Header

    private func header(accent: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            NodeIconTile(kind: node.kind)
            VStack(alignment: .leading, spacing: 6) {
                Text(node.name)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .lineLimit(2)
                KindBadge(kind: node.kind)
            }
            Spacer()
        }
    }

    // MARK: - About card

    private func aboutCard(accent: Color) -> some View {
        SectionCard(title: "About", systemImage: "person.2.fill", accent: accent) {
            Text(node.description)
                .font(.body)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Note card

    private func noteCard(accent: Color) -> some View {
        SectionCard(title: "About Agents", systemImage: "info.circle", accent: .secondary) {
            Text("Agents are dispatched automatically by Claude — nothing to inject.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
