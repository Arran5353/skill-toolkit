import Foundation

public struct MCPServerInfo: Equatable, Sendable {
    public let name: String       // server name (json key)
    public let transport: String  // "http" / "stdio" / ""
    public let endpoint: String   // url or command, may be ""

    public init(name: String, transport: String, endpoint: String) {
        self.name = name
        self.transport = transport
        self.endpoint = endpoint
    }
}

public struct MCPScanner {
    /// Parse a .mcp.json string into servers.
    /// Supports {name:{...}} and {mcpServers:{name:{...}}}.
    public static func parse(_ json: String) -> [MCPServerInfo] {
        guard let data = json.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              !top.isEmpty else { return [] }

        // If top-level has "mcpServers" key (object), use that; else use top-level
        let servers: [String: Any]
        if let wrapped = top["mcpServers"] as? [String: Any] {
            servers = wrapped
        } else {
            servers = top
        }

        var result: [MCPServerInfo] = []
        for (name, value) in servers {
            guard let cfg = value as? [String: Any] else { continue }
            let transport: String
            if let t = cfg["type"] as? String {
                transport = t
            } else if cfg["command"] != nil {
                transport = "stdio"
            } else {
                transport = ""
            }
            let endpoint = (cfg["url"] as? String) ?? (cfg["command"] as? String) ?? ""
            result.append(MCPServerInfo(name: name, transport: transport, endpoint: endpoint))
        }

        return result.sorted { $0.name < $1.name }
    }
}
