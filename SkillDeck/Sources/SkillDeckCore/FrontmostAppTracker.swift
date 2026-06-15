import AppKit

/// Tracks the app that was frontmost before SkillDeck took focus, so we can return focus to it.
@MainActor
public final class FrontmostAppTracker {
    public private(set) var previousApp: NSRunningApplication?
    private var observer: NSObjectProtocol?

    public init() {}

    public func start() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                Task { @MainActor [weak self] in
                    self?.previousApp = app
                }
            }
        }
    }

    public func stop() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
