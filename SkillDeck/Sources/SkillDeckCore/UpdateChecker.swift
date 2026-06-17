import Foundation

public struct UpdateChecker {
    /// Compares dotted numeric versions ("1.2.0" vs "1.10.0"). Leading "v" tolerated.
    /// Returns true if `latest` is strictly newer than `current`.
    public static func isNewer(latest: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "v ")).split(separator: ".")
             .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        }
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - Release + Network

extension UpdateChecker {
    public struct Release: Sendable, Equatable {
        public let version: String   // tag_name, e.g. "v1.1.0"
        public let url: String       // html_url to the release page
    }

    /// The GitHub releases/latest endpoint for this repo.
    public static let latestReleaseAPI =
        "https://api.github.com/repos/Arran5353/skill-toolkit/releases/latest"
    public static let releasesPage =
        "https://github.com/Arran5353/skill-toolkit/releases/latest"

    /// Fetches the latest release. Returns nil on any network/parse error (silent failure).
    public static func fetchLatest(from urlString: String = latestReleaseAPI) async -> Release? {
        guard let url = URL(string: urlString) else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        let page = (obj["html_url"] as? String) ?? releasesPage
        return Release(version: tag, url: page)
    }

    /// Returns the newer release if one exists, else nil. `current` is the running version.
    public static func checkForUpdate(current: String,
                                      from urlString: String = latestReleaseAPI) async -> Release? {
        guard let latest = await fetchLatest(from: urlString) else { return nil }
        return isNewer(latest: latest.version, than: current) ? latest : nil
    }
}

// MARK: - Fallback version

extension UpdateChecker {
    /// Hardcoded fallback used when running via `swift run` (no app bundle). Keep in sync with
    /// package.sh VERSION at release time.
    public static let fallbackVersion = "1.0.0"
}
