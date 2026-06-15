import SwiftUI
import SkillDeckCore

// MARK: - NodeRow (shared with ListView)

struct NodeRow: View {
    let node: Node
    let isFavorite: Bool

    var body: some View {
        HStack {
            Image(systemName: iconName(for: node.kind))
                .foregroundStyle(iconColor(for: node.kind))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name).font(.body)
                if !node.description.isEmpty {
                    Text(node.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow)
            }
        }
    }

    private func iconName(for kind: NodeKind) -> String {
        switch kind {
        case .marketplace:     return "globe"
        case .plugin:          return "puzzlepiece.extension"
        case .skill:           return "sparkles"
        case .command:         return "terminal"
        case .builtinCommand:  return "wrench.and.screwdriver"
        case .localSkill:      return "folder.badge.person.crop"
        }
    }

    private func iconColor(for kind: NodeKind) -> Color {
        switch kind {
        case .marketplace: return .blue
        case .plugin:      return .purple
        case .skill:       return .orange
        case .command:     return .primary
        case .builtinCommand: return .gray
        case .localSkill:  return .green
        }
    }
}

// MARK: - TreeNode wrapper (needed for OutlineGroup which requires a KeyPath)

struct TreeNode: Identifiable {
    let node: Node
    var children: [TreeNode]?   // nil = leaf for OutlineGroup disclosure

    var id: String { node.id }
}

// MARK: - TreeListView

struct TreeListView: View {
    let store: AppStore
    @Binding var selection: String?

    private func buildTreeNode(_ node: Node) -> TreeNode {
        let kids = store.children(of: node.id).filter { child in
            child.isLeaf || child.status == .installed
        }
        if kids.isEmpty {
            return TreeNode(node: node, children: nil)
        }
        return TreeNode(node: node, children: kids.map { buildTreeNode($0) })
    }

    private var shownRoots: [Node] {
        store.rootNodes().filter { root in hasShowableDescendant(root) }
    }

    private func hasShowableDescendant(_ node: Node) -> Bool {
        if node.isLeaf { return true }
        if node.kind == .plugin && node.status == .installed { return true }
        return store.children(of: node.id).contains { hasShowableDescendant($0) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(shownRoots) { root in
                RootSection(store: store, root: root, buildTreeNode: buildTreeNode)
            }
        }
    }
}

// MARK: - Root Section

private struct RootSection: View {
    let store: AppStore
    let root: Node
    let buildTreeNode: (Node) -> TreeNode

    private var topLevelTreeNodes: [TreeNode] {
        store.children(of: root.id)
            .filter { $0.isLeaf || $0.status == .installed }
            .map { buildTreeNode($0) }
    }

    var body: some View {
        Section(root.name) {
            OutlineGroup(topLevelTreeNodes, children: \.children) { treeNode in
                NodeRow(
                    node: treeNode.node,
                    isFavorite: treeNode.node.isLeaf && store.isFavorite(treeNode.node.id)
                )
                .tag(treeNode.node.id)
            }
        }
    }
}
