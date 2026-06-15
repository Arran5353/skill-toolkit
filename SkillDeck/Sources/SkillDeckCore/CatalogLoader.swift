import Foundation

/// Combines all scanners into the final node tree + warnings.
public struct CatalogLoader {
    public struct Result: Equatable {
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
        let nodes = TreeBuilder.build(skillItems: leafScan.items, marketplaceNodes: mpScan.nodes)
        return Result(nodes: nodes, warnings: leafScan.warnings + mpScan.warnings)
    }
}
