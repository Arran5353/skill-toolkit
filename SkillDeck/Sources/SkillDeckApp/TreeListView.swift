import SwiftUI
import SkillDeckCore

// MARK: - NodeRow (shared with ListView)

struct NodeRow: View {
    let node: Node
    let isFavorite: Bool

    var body: some View {
        let accent = NodeTheme.accent(node.kind)
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(accent.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: NodeTheme.icon(node.kind))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(node.name)
                    .font(.system(.body, design: .rounded).weight(.medium))
                if !node.description.isEmpty {
                    Text(node.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 2)
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
