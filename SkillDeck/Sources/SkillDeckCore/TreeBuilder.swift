import Foundation

/// Assembles v1 SkillItems + marketplace/plugin nodes into one flat [Node] with parentID wiring.
/// Side-branch roots: root|local, root|project, root|builtin. Installed plugin leaves hang under
/// their plugin node (mp|<marketplace>|plugin|<name>) when known, else a synthesized plugin|<name>.
public struct TreeBuilder {
    public static let localRootID = "root|local"
    public static let projectRootID = "root|project"
    public static let builtinRootID = "root|builtin"

    public static func build(skillItems: [SkillItem], marketplaceNodes: [Node]) -> [Node] {
        var out: [Node] = []
        var seen = Set<String>()

        func add(_ node: Node) {
            guard seen.insert(node.id).inserted else { return }
            out.append(node)
        }

        // marketplace + plugin nodes first; index plugin nodes by name for leaf parenting
        var pluginParentByName: [String: String] = [:]   // pluginName -> plugin node id
        for n in marketplaceNodes {
            add(n)
            // KNOWN LIMITATION: keyed by bare plugin name. If two marketplaces ever share a
            // plugin name, last-write-wins and an installed plugin's leaves may be parented to
            // the wrong marketplace's plugin node. Harmless today (one real marketplace); the
            // leaf + injection stay correct, only tree placement would be off. Fix requires
            // Scanner to record each plugin's marketplace. Tracked for a future revision.
            if n.kind == .plugin { pluginParentByName[n.name] = n.id }
        }

        // Side-branch roots are top-level container Nodes (kind .marketplace) created lazily.
        func ensureRoot(_ id: String, _ title: String) {
            if !seen.contains(id) {
                add(Node(id: id, kind: .marketplace, name: title, description: "",
                         status: .notApplicable, parentID: nil))
            }
        }

        var projectNames: Set<String> = []

        for item in skillItems {
            let parentID: String
            let kind: NodeKind
            switch item.scope {
            case .builtin:
                ensureRoot(builtinRootID, "Built-in commands")
                parentID = builtinRootID
                kind = .builtinCommand
            case .project(let projectName):
                ensureRoot(projectRootID, "Project")   // placeholder; renamed below
                projectNames.insert(projectName)
                parentID = projectRootID
                kind = (item.kind == .skill) ? .skill : .command
            case .user:
                if let plugin = item.pluginName {
                    if let known = pluginParentByName[plugin] {
                        parentID = known
                    } else {
                        let synth = "plugin|\(plugin)"
                        if !seen.contains(synth) {
                            add(Node(id: synth, kind: .plugin, name: plugin, description: "",
                                     status: .installed, parentID: nil,
                                     marketplaceName: nil, installRef: nil))
                        }
                        parentID = synth
                    }
                    kind = (item.kind == .skill) ? .skill : .command
                } else {
                    ensureRoot(localRootID, "My local skills")
                    parentID = localRootID
                    kind = (item.kind == .skill) ? .localSkill : .command
                }
            }
            add(Node(id: item.id, kind: kind, name: item.name, description: item.description,
                     status: .notApplicable, parentID: parentID,
                     body: item.body, insertText: item.insertText, filePath: item.filePath))
        }

        // Rename the project root to include the project name(s) so users know what it is.
        if !projectNames.isEmpty, let idx = out.firstIndex(where: { $0.id == projectRootID }) {
            let label: String
            if projectNames.count == 1, let name = projectNames.first {
                // Use only the last path component for brevity (e.g. "Desktop/Cocktail-expert" → "Cocktail-expert")
                let shortName = name.split(separator: "/").last.map(String.init) ?? name
                label = "Project: \(shortName)"
            } else {
                label = "Projects (\(projectNames.count))"
            }
            let old = out[idx]
            out[idx] = Node(id: old.id, kind: old.kind, name: label, description: old.description,
                            status: old.status, parentID: old.parentID)
        }

        return out
    }
}
