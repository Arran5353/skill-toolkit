import Foundation

/// Combines all scanners into the final node tree + warnings.
public struct CatalogLoader {
    public struct Result: Equatable, Sendable {
        public let nodes: [Node]
        public let warnings: [ScanWarning]
    }

    public static func loadDefault(projectDirs: [String]) -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return load(
            userSkillsDir: "\(home)/.claude/skills",
            pluginsCacheDir: "\(home)/.claude/plugins/cache",
            marketplacesDir: "\(home)/.claude/plugins/marketplaces",
            installedPluginsPath: "\(home)/.claude/plugins/installed_plugins.json",
            projectDirs: projectDirs)
    }

    public static func load(userSkillsDir: String, pluginsCacheDir: String,
                            marketplacesDir: String, installedPluginsPath: String,
                            projectDirs: [String]) -> Result {
        let installed = InstalledPluginsIndex.load(from: installedPluginsPath)
        let leafScan = Scanner.scan(userSkillsDir: userSkillsDir, pluginsCacheDir: pluginsCacheDir,
                                    projectDirs: projectDirs, includeBuiltins: true)
        let mpScan = MarketplaceScanner.scan(marketplacesDir: marketplacesDir, installed: installed)
        var nodes = TreeBuilder.build(skillItems: leafScan.items, marketplaceNodes: mpScan.nodes)
        nodes += scanMCPNodes(pluginsCacheDir: pluginsCacheDir)
        return Result(nodes: nodes, warnings: leafScan.warnings + mpScan.warnings)
    }

    // MARK: - MCP server node scanner

    /// Walk <cache>/<marketplace>/<plugin>/<ver>/.mcp.json for each installed plugin version dir
    /// and build .mcpServer leaf Nodes parented to the plugin node.
    private static func scanMCPNodes(pluginsCacheDir: String) -> [Node] {
        let fm = FileManager.default
        var result: [Node] = []

        guard let mpDirs = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: pluginsCacheDir),
            includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }

        for mpDir in mpDirs {
            guard (try? mpDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            let marketplace = mpDir.lastPathComponent

            guard let pluginDirs = try? fm.contentsOfDirectory(
                at: mpDir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for pluginDir in pluginDirs {
                guard (try? pluginDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let plugin = pluginDir.lastPathComponent

                // Use the highest version dir (same strategy as Scanner)
                guard let versionDirs = try? fm.contentsOfDirectory(
                    at: pluginDir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
                let sorted = versionDirs
                    .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                    .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
                guard let versionDir = sorted.first else { continue }

                let mcpPath = versionDir.appendingPathComponent(".mcp.json")
                guard let jsonString = try? String(contentsOf: mcpPath, encoding: .utf8) else { continue }

                let servers = MCPScanner.parse(jsonString)
                for server in servers {
                    let desc = server.transport.isEmpty
                        ? server.endpoint
                        : "\(server.transport.uppercased()) · \(server.endpoint)"
                    let node = Node(
                        id: "mcp|\(marketplace)|\(plugin)|\(server.name)",
                        kind: .mcpServer,
                        name: server.name,
                        description: desc,
                        status: .notApplicable,
                        parentID: Node.pluginID(marketplace: marketplace, plugin: plugin),
                        body: nil,
                        insertText: nil,
                        filePath: mcpPath.path
                    )
                    result.append(node)
                }
            }
        }

        return result
    }
}
