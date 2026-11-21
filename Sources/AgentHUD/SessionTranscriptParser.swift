import Foundation

enum SessionTranscriptParser {
    private struct CacheEntry {
        let fileSize: UInt64
        let headBytes: Int
        let tailBytes: Int
        let providerIsRunning: Bool
        let parsedAt: Date
        let session: AgentSession?
    }

    private static let lock = NSLock()
    private static var cache: [String: CacheEntry] = [:]

    static func parse(
        provider: AgentProvider,
        fileURL: URL,
        modifiedAt: Date,
        providerIsRunning: Bool,
        now: Date = .now,
        headBytes: Int = 96 * 1024,
        tailBytes: Int = 768 * 1024
    ) -> AgentSession? {
        guard let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.uint64Value else {
            return nil
        }
        let key = fileURL.path
        lock.lock()
        let cached = cache[key]
        lock.unlock()

        if let cached,
           cached.fileSize == fileSize,
           cached.headBytes == headBytes,
           cached.tailBytes == tailBytes,
           cached.providerIsRunning == providerIsRunning,
           now.timeIntervalSince(cached.parsedAt) < 1,
           let session = cached.session {
            // Parsing history is deterministic for an unchanged append-only log.
            // Only the time-derived online flag needs to follow the current scan.
            return replacingLiveFlag(of: session, isLive: providerIsRunning && now.timeIntervalSince(session.lastActivityAt) < 600)
        }
        if let cached,
           cached.fileSize == fileSize,
           cached.providerIsRunning == providerIsRunning,
           now.timeIntervalSince(cached.parsedAt) < 1 {
            return nil
        }

        guard let records = try? LogFileReader.readJSONLines(
            from: fileURL,
            headBytes: headBytes,
            tailBytes: tailBytes
        ) else {
            return nil
        }
        let session: AgentSession?
        switch provider {
        case .codex:
            session = CodexAdapter.parse(
                records: records,
                fileURL: fileURL,
                modifiedAt: modifiedAt,
                providerIsRunning: providerIsRunning,
                now: now
            )
        case .claude:
            session = ClaudeAdapter.parse(
                records: records,
                fileURL: fileURL,
                modifiedAt: modifiedAt,
                providerIsRunning: providerIsRunning,
                now: now
            )
        case .pi, .opencode:
            return nil
        }
        lock.lock()
        cache[key] = CacheEntry(
            fileSize: fileSize,
            headBytes: headBytes,
            tailBytes: tailBytes,
            providerIsRunning: providerIsRunning,
            parsedAt: now,
            session: session
        )
        lock.unlock()
        return session
    }

    private static func replacingLiveFlag(of session: AgentSession, isLive: Bool) -> AgentSession {
        AgentSession(
            id: session.id,
            provider: session.provider,
            providerSessionID: session.providerSessionID,
            projectName: session.projectName,
            projectPath: session.projectPath,
            title: session.title,
            titleSource: session.titleSource,
            status: session.status,
            confidence: session.confidence,
            currentAction: session.currentAction,
            currentFiles: session.currentFiles,
            startedAt: session.startedAt,
            lastActivityAt: session.lastActivityAt,
            completedAt: session.completedAt,
            runs: session.runs,
            latestUserPrompt: session.latestUserPrompt,
            sourcePath: session.sourcePath,
            isLive: isLive,
            git: session.git
        )
    }
}
