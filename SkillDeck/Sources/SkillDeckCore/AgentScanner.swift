import Foundation

public struct AgentInfo: Equatable, Sendable {
    public let name: String
    public let description: String
    public let model: String?

    public init(name: String, description: String, model: String?) {
        self.name = name
        self.description = description
        self.model = model
    }
}

public struct AgentScanner {
    /// Scan a plugin version directory for agent markdown files.
    /// Looks in <dir>/agents/*.md and at plugin.json-declared agent paths.
    /// Dedupes by name and returns sorted by name.
    public static func scan(pluginVersionDir: String) -> [AgentInfo] {
        let fm = FileManager.default
        let base = URL(fileURLWithPath: pluginVersionDir)
        var byName: [String: AgentInfo] = [:]

        // 1. Standard agents directory: <dir>/agents/*.md
        let agentsDir = base.appendingPathComponent("agents")
        if let entries = try? fm.contentsOfDirectory(
            at: agentsDir,
            includingPropertiesForKeys: [.isRegularFileKey]) {
            for entry in entries where entry.pathExtension == "md" {
                if let info = parseAgentFile(entry) {
                    if byName[info.name] == nil {
                        byName[info.name] = info
                    }
                }
            }
        }

        // 2. plugin.json-declared agent paths
        let pluginJsonPath = base.appendingPathComponent(".claude-plugin/plugin.json")
        if let data = try? Data(contentsOf: pluginJsonPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let declaredPaths: [String]
            if let arr = json["agents"] as? [String] {
                declaredPaths = arr
            } else if let str = json["agents"] as? String {
                declaredPaths = [str]
            } else {
                declaredPaths = []
            }
            for rel in declaredPaths {
                let resolved = base.appendingPathComponent(rel).standardizedFileURL
                if let info = parseAgentFile(resolved), byName[info.name] == nil {
                    byName[info.name] = info
                }
            }
        }

        return byName.values.sorted { $0.name < $1.name }
    }

    // MARK: - Private helpers

    private static func parseAgentFile(_ url: URL) -> AgentInfo? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let parsed = FrontmatterParser.parse(text)
        let fallbackName = url.deletingPathExtension().lastPathComponent
        let name = parsed.frontmatter["name"] ?? fallbackName
        let description = parsed.frontmatter["description"] ?? ""
        let model = parsed.frontmatter["model"]
        return AgentInfo(name: name, description: description, model: model)
    }
}
