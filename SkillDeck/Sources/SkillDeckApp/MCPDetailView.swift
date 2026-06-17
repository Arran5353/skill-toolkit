import SwiftUI
import SkillDeckCore

/// Read-only detail card for an MCP server node.
/// Shows the server name, transport and endpoint — no inject/copy buttons.
struct MCPDetailView: View {
    let node: Node

    var body: some View {
        let accent = NodeTheme.accent(node.kind)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(accent: accent)
                connectionCard(accent: accent)
                noteCard(accent: accent)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(backdrop(accent))
    }

    // MARK: - Header

    private func header(accent: Color) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(accent.gradient.opacity(0.9))
                    .frame(width: 52, height: 52)
                    .shadow(color: accent.opacity(0.35), radius: 8, y: 3)
                Image(systemName: NodeTheme.icon(node.kind))
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(node.name)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .lineLimit(2)
                KindBadge(kind: node.kind)
            }
            Spacer()
        }
    }

    // MARK: - Connection card

    private func connectionCard(accent: Color) -> some View {
        SectionCard(title: "Connection", systemImage: "network", accent: accent) {
            Text(node.description)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Note card

    private func noteCard(accent: Color) -> some View {
        SectionCard(title: "About MCP Servers", systemImage: "info.circle", accent: .secondary) {
            Text("Provided as an MCP tool server — invoked automatically by Claude; nothing to inject.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Backdrop

    private func backdrop(_ accent: Color) -> some View {
        LinearGradient(
            colors: [accent.opacity(0.06), .clear],
            startPoint: .top, endPoint: .center
        )
        .ignoresSafeArea()
    }
}
