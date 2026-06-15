import Foundation
import Observation

@MainActor
@Observable
public final class Installer {
    public enum State: Equatable, Sendable {
        case idle, installing, succeeded, failed(String)
    }

    public private(set) var states: [String: State] = [:]   // keyed by plugin node id

    public init() {}

    /// Pure: arguments to pass to the `claude` executable for an install.
    public nonisolated static func installArguments(installRef: String) -> [String] {
        ["plugin", "install", installRef]
    }

    public nonisolated static var fallbackClaudePath: String {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/claude").path
    }

    /// Resolves the claude executable: the fallback path if executable, else `which claude`.
    nonisolated static func resolveClaudeURL() -> URL? {
        let fallback = URL(fileURLWithPath: fallbackClaudePath)
        if FileManager.default.isExecutableFile(atPath: fallback.path) { return fallback }
        let which = Process()
        which.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        which.arguments = ["claude"]
        let pipe = Pipe()
        which.standardOutput = pipe
        try? which.run()
        which.waitUntilExit()
        if which.terminationStatus == 0,
           let data = try? pipe.fileHandleForReading.readToEnd(),
           let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            return URL(fileURLWithPath: s)
        }
        return nil
    }

    public static var isClaudeAvailable: Bool { resolveClaudeURL() != nil }

    /// Runs `claude plugin install <installRef>` in the background and tracks state by node id.
    public func install(_ node: Node) async {
        guard let ref = node.installRef else { return }
        states[node.id] = .installing
        let result = await Self.runInstall(ref: ref)
        states[node.id] = result
    }

    private nonisolated static func runInstall(ref: String) async -> State {
        guard let claude = resolveClaudeURL() else {
            return .failed("claude CLI not found")
        }
        return await withCheckedContinuation { cont in
            let proc = Process()
            proc.executableURL = claude
            proc.arguments = installArguments(installRef: ref)
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = Pipe()
            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    cont.resume(returning: .succeeded)
                } else {
                    let data = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
                    let msg = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? "exit \(p.terminationStatus)"
                    cont.resume(returning: .failed(msg.isEmpty ? "exit \(p.terminationStatus)" : msg))
                }
            }
            do { try proc.run() } catch {
                cont.resume(returning: .failed(error.localizedDescription))
            }
        }
    }
}
