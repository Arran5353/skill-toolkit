import SwiftUI
import SkillDeckCore

struct PluginDetailView: View {
    let store: AppStore
    let node: Node
    let claudeAvailable: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(node.name).font(.title.bold())

                HStack(spacing: 6) {
                    Image(systemName: node.status == .installed
                          ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(node.status == .installed ? .green : .secondary)
                    Text(node.status == .installed ? "Installed" : "Not installed")
                        .font(.subheadline)
                        .foregroundStyle(node.status == .installed ? .green : .secondary)
                }

                if !node.description.isEmpty {
                    Text(node.description)
                        .font(.body)
                }

                if node.status != .installed {
                    Divider()
                    InstallButton(store: store, node: node, claudeAvailable: claudeAvailable)

                    if !claudeAvailable {
                        Text("claude CLI not found — install claude to enable plugin installation.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
