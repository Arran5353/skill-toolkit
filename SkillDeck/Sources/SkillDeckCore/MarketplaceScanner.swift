import Foundation

/// Reads marketplace manifests into marketplace + plugin Nodes.
public struct MarketplaceScanner {
    public struct Result: Equatable {
        public let nodes: [Node]
        public let warnings: [ScanWarning]
    }

    private struct Manifest: Decodable {
        let name: String
        let plugins: [Entry]
        struct Entry: Decodable { let name: String; let description: String? }
    }

    /// Production convenience using the standard ~/.claude layout.
    public static func scanDefault(installed: Set<String>) -> Result {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return scan(marketplacesDir: "\(home)/.claude/plugins/marketplaces", installed: installed)
    }

    public static func scan(marketplacesDir: String, installed: Set<String>) -> Result {
        let fm = FileManager.default
        var nodes: [Node] = []
        var warnings: [ScanWarning] = []

        guard let mpDirs = try? fm.contentsOfDirectory(
            at: URL(fileURLWithPath: marketplacesDir),
            includingPropertiesForKeys: [.isDirectoryKey]) else {
            return Result(nodes: [], warnings: [])
        }

        for mpDir in mpDirs {
            let manifestPath = mpDir.appendingPathComponent(".claude-plugin/marketplace.json")
            guard fm.fileExists(atPath: manifestPath.path) else { continue }
            guard let data = try? Data(contentsOf: manifestPath),
                  let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
                warnings.append(ScanWarning(filePath: manifestPath.path,
                                            message: "Could not parse marketplace manifest"))
                continue
            }
            let mpName = manifest.name
            nodes.append(Node(id: Node.marketplaceID(mpName), kind: .marketplace,
                              name: mpName, description: "", status: .notApplicable,
                              parentID: nil))
            for entry in manifest.plugins {
                let ref = "\(entry.name)@\(mpName)"
                let status: InstallStatus = installed.contains(ref) ? .installed : .available
                nodes.append(Node(
                    id: Node.pluginID(marketplace: mpName, plugin: entry.name),
                    kind: .plugin, name: entry.name,
                    description: entry.description ?? "", status: status,
                    parentID: Node.marketplaceID(mpName),
                    marketplaceName: mpName, installRef: ref))
            }
        }
        return Result(nodes: nodes, warnings: warnings)
    }
}
