import Foundation

/// Reads installed_plugins.json and exposes the set of installed "<plugin>@<marketplace>" refs.
public struct InstalledPluginsIndex {
    public static func load(from path: String) -> Set<String> {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let plugins = obj["plugins"] as? [String: Any] else {
            return []
        }
        return Set(plugins.keys)
    }
}
