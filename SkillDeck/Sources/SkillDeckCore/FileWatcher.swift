import Foundation
import CoreServices

/// Watches directories via FSEvents and calls `onChange` (debounced) on the main queue.
public final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let onChange: () -> Void
    private var debounceWork: DispatchWorkItem?

    public init(paths: [String], onChange: @escaping () -> Void) {
        self.paths = paths
        self.onChange = onChange
    }

    public func start() {
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info = info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.scheduleDebounced()
        }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let existing = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existing.isEmpty else { return }
        stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            existing as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5, FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone))
        guard let stream = stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleDebounced() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onChange() }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    deinit { stop() }
}
