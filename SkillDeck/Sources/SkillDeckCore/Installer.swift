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

    /// Maximum seconds to wait for `claude plugin install` before killing the child process.
    /// Exposed as `internal` so unit tests can assert it is positive.
    public nonisolated static let installTimeout: TimeInterval = _installTimeout

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
            let outPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = outPipe
            // Redirect stdin to /dev/null so the child can never block waiting for input.
            proc.standardInput = FileHandle.nullDevice

            // Drain BOTH pipes concurrently on background queues. A CLI like `claude` can
            // write more than the ~64KB pipe buffer to stdout; if we don't read it, the
            // child blocks on write, never exits, terminationHandler never fires, and the
            // install spins forever. Collecting on dispatch queues avoids that deadlock.
            let outData = LockedData()
            let errData = LockedData()
            let group = DispatchGroup()
            for (handle, sink) in [(outPipe.fileHandleForReading, outData),
                                   (errPipe.fileHandleForReading, errData)] {
                group.enter()
                DispatchQueue.global(qos: .utility).async {
                    sink.set((try? handle.readToEnd()) ?? Data())
                    group.leave()
                }
            }

            // Exactly-once resume guard: whichever path fires first (terminationHandler,
            // timeout, or run() throw) wins; all subsequent calls are no-ops.
            let resumed = LockedFlag()
            // @Sendable so it can be captured in @Sendable closures (terminationHandler,
            // DispatchWorkItem, etc.) without Swift 6 concurrency errors.
            let resumeOnce: @Sendable (State) -> Void = { state in
                guard resumed.setIfFalse() else { return }
                cont.resume(returning: state)
            }

            // Box DispatchWorkItem in an @unchecked Sendable wrapper so it can be captured
            // across concurrency boundaries without a Swift 6 error.
            // DispatchWorkItem itself is thread-safe for cancel() calls.
            let timeoutBox = SendableBox<DispatchWorkItem?>(nil)

            proc.terminationHandler = { p in
                // Cancel any pending timeout work item so we don't needlessly terminate
                // a process that has already exited cleanly.
                timeoutBox.value?.cancel()
                // Wait for both readers to finish so output is complete and FDs are closed.
                group.wait()
                if p.terminationStatus == 0 {
                    resumeOnce(.succeeded)
                } else {
                    let msg = (String(data: errData.get(), encoding: .utf8) ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    resumeOnce(.failed(msg.isEmpty ? "exit \(p.terminationStatus)" : msg))
                }
            }

            do {
                try proc.run()
            } catch {
                resumeOnce(.failed(error.localizedDescription))
                return
            }

            // Schedule a timeout after proc.run() succeeds. terminate() causes the process
            // to exit, which fires terminationHandler — the resumed-once flag ensures only
            // one of them actually resumes the continuation.
            let timeoutItem = DispatchWorkItem {
                if proc.isRunning { proc.terminate() }
                // terminationHandler will also call resumeOnce after terminate(); call it
                // here too so the timeout wins the race if the process exited between the
                // isRunning check and terminate(). The loser is always a no-op.
                resumeOnce(.failed("Install timed out after \(Int(installTimeout))s"))
            }
            timeoutBox.value = timeoutItem
            DispatchQueue.global().asyncAfter(deadline: .now() + installTimeout,
                                              execute: timeoutItem)
        }
    }
}

// MARK: - File-level constants (avoid @MainActor isolation on Installer statics)

/// Backing value for `Installer.installTimeout`. Defined at file scope so it can be
/// referenced from `nonisolated` contexts without actor-isolation errors.
private let _installTimeout: TimeInterval = 180

// MARK: - Helpers

/// Minimal thread-safe Data box for collecting pipe output from a background queue.
private final class LockedData: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func set(_ d: Data) { lock.lock(); data = d; lock.unlock() }
    func get() -> Data { lock.lock(); defer { lock.unlock() }; return data }
}

/// Thread-safe Bool flag that can only transition false → true once.
/// Used to guarantee a continuation is resumed exactly once.
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    /// Sets the flag to true if it was false. Returns true if this call won the race.
    func setIfFalse() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if value { return false }
        value = true
        return true
    }
}

/// Minimal @unchecked Sendable wrapper that lets a non-Sendable value (e.g. DispatchWorkItem)
/// be captured across concurrency boundaries. The caller is responsible for thread safety.
private final class SendableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) { self.value = value }
}
