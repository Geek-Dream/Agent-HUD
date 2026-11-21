import Foundation

/// Directory-level file events avoid waiting for the periodic scanner fallback.
/// The watcher only reports paths; parsing stays in SessionScanner off-main.
final class SessionActivityWatcher {
    var onChange: (() -> Void)?
    private let fileManager: FileManager
    private let roots: [URL]?
    private var streams: [FSEventStreamRef] = []
    private var pendingTask: Task<Void, Never>?
    private var watching = false

    init(fileManager: FileManager = .default, roots: [URL]? = nil) {
        self.fileManager = fileManager
        self.roots = roots
    }

    deinit {
        pendingTask?.cancel()
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func start() {
        guard !watching else { return }
        watching = true
        for path in watchedPaths {
            let paths = [path] as CFArray
            var context = FSEventStreamContext()
            context.info = Unmanaged.passUnretained(self).toOpaque()
            guard let stream = FSEventStreamCreate(
                nil,
                { _, info, _, eventPaths, _, _ in
                    guard let info, let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String],
                          !paths.isEmpty else { return }
                    let watcher = Unmanaged<SessionActivityWatcher>.fromOpaque(info).takeUnretainedValue()
                    Task { @MainActor [weak watcher] in
                        watcher?.scheduleRefresh()
                    }
                },
                &context,
                paths,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.12,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
            ) else {
                continue
            }
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
            streams.append(stream)
        }
    }

    func stop() {
        pendingTask?.cancel()
        pendingTask = nil
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
        watching = false
    }

    private var watchedPaths: [String] {
        if let roots { return roots.map(\.path) }
        let home = fileManager.homeDirectoryForCurrentUser
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let candidates = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".local/share/opencode", isDirectory: true),
            applicationSupport.appendingPathComponent("orca/agent-hooks", isDirectory: true),
            applicationSupport.appendingPathComponent("orca/profiles/local-default", isDirectory: true)
        ]
        var result = candidates.filter { fileManager.fileExists(atPath: $0.path) }
        // A source may be created after launch. Watching its existing parent means
        // the first session is still observed without polling new directories.
        if !result.contains(where: { $0.path.hasSuffix(".codex/sessions") }) {
            result.append(home.appendingPathComponent(".codex", isDirectory: true))
        }
        return Array(Set(result.filter { fileManager.fileExists(atPath: $0.path) }.map(\.path))).sorted()
    }

    private func scheduleRefresh() {
        guard pendingTask == nil else { return }
        pendingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.pendingTask = nil
            self?.onChange?()
        }
    }
}
