import Foundation

public struct ProjectDiscovery {
    private struct Line: Decodable { let timestamp: Double?; let project: String? }

    /// Returns unique project paths ordered by most-recent timestamp first, up to `limit`.
    public static func recentProjects(historyPath: String, limit: Int) -> [String] {
        guard let content = try? String(contentsOfFile: historyPath, encoding: .utf8) else {
            return []
        }
        var latest: [String: Double] = [:]
        let decoder = JSONDecoder()
        for raw in content.split(separator: "\n") {
            guard let data = raw.data(using: .utf8),
                  let line = try? decoder.decode(Line.self, from: data),
                  let project = line.project else { continue }
            let ts = line.timestamp ?? 0
            if let existing = latest[project] { latest[project] = max(existing, ts) }
            else { latest[project] = ts }
        }
        return latest.sorted { $0.value > $1.value }.prefix(limit).map { $0.key }
    }
}
