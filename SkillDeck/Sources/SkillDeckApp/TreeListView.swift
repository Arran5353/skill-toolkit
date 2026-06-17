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
    var leafKinds: Set<NodeKind>? = nil       // nil = all leaf kinds (the "All" view)
    var rootFilter: ((Node) -> Bool)? = nil   // optional: restrict which roots to show

    /// Recursively build a TreeNode, keeping only subtrees that have matching leaves.
    /// When leafKinds == nil, all leaves match (existing "All" behavior).
    private func matchingTree(_ node: Node) -> TreeNode? {
        let children = store.children(of: node.id)

        if node.isLeaf {
            // Determine if this leaf matches the filter
            let selfMatches: Bool
            if let kinds = leafKinds {
                selfMatches = kinds.contains(node.kind)
            } else {
                // nil = all leaves match (All view)
                selfMatches = true
            }
            if selfMatches {
                return TreeNode(node: node, children: nil)
            } else {
                return nil
            }
        } else {
            // Container node: filter children that are either leaves or installed plugins
            // (mirrors the original buildTreeNode filter)
            let eligibleChildren: [Node]
            if leafKinds == nil {
                // Original "All" behavior: keep installed plugins and leaves
                eligibleChildren = children.filter { $0.isLeaf || $0.status == .installed }
            } else {
                // Filtered view: recurse into all children; matchingTree will prune empties
                eligibleChildren = children
            }

            let builtChildren = eligibleChildren.compactMap { matchingTree($0) }

            // A container is shown if it has matching descendants
            if builtChildren.isEmpty {
                return nil
            }
            return TreeNode(node: node, children: builtChildren)
        }
    }

    private var shownRoots: [Node] {
        var roots = store.rootNodes()
        if let rf = rootFilter {
            roots = roots.filter(rf)
        }
        return roots.filter { matchingTree($0) != nil }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(shownRoots) { root in
                RootSection(store: store, root: root, matchingTree: matchingTree)
            }
        }
    }
}

// MARK: - Root Section

private struct RootSection: View {
    let store: AppStore
    let root: Node
    let matchingTree: (Node) -> TreeNode?

    private var topLevelTreeNodes: [TreeNode] {
        store.children(of: root.id).compactMap { matchingTree($0) }
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
