import Foundation

final class SessionScanner {
    private struct GitCacheEntry {
        let value: GitContext?
        let checkedAt: Date
    }

    private let fileManager = FileManager.default
    private var gitCache: [String: GitCacheEntry] = [:]
    private let cacheLock = NSLock()

    func scan(now: Date = .now) -> DashboardSnapshot {
        let home = fileManager.homeDirectoryForCurrentUser
        let processes = ProcessPresence.detect()
        let openCodeSessions = OpenCodeSessionSource.scan(
            providerIsRunning: processes.opencode,
            now: now
        )

        if let sessions = OrcaSessionSource.scan(now: now) {
            var currentSessions = deduplicate(sessions + openCodeSessions)
            currentSessions.sort(by: sessionSort)
            currentSessions = Array(currentSessions.prefix(24))
            currentSessions = attachGitContexts(to: currentSessions, now: now)
            return DashboardSnapshot(sessions: currentSessions, scannedAt: now)
        }

        let codexRoot = home.appendingPathComponent(".codex/sessions", isDirectory: true)
        let claudeRoot = home.appendingPathComponent(".claude/projects", isDirectory: true)
        let cutoff = now.addingTimeInterval(-7 * 86_400)

        let codexFiles = recentFiles(
            in: codexRoot,
            modifiedAfter: cutoff,
            limit: 36
        )
        let claudeFiles = recentFiles(
            in: claudeRoot,
            modifiedAfter: cutoff,
            limit: 36
        )

        var sessions: [AgentSession] = []

        for file in codexFiles {
            guard let records = try? LogFileReader.readJSONLines(from: file) else {
                continue
            }
            let modifiedAt = modificationDate(file) ?? now
            if let session = CodexAdapter.parse(
                records: records,
                fileURL: file,
                modifiedAt: modifiedAt,
                providerIsRunning: processes.codex,
                now: now
            ) {
                sessions.append(session)
            }
        }

        for file in claudeFiles {
            guard let records = try? LogFileReader.readJSONLines(from: file) else {
                continue
            }
            let modifiedAt = modificationDate(file) ?? now
            if let session = ClaudeAdapter.parse(
                records: records,
                fileURL: file,
                modifiedAt: modifiedAt,
                providerIsRunning: processes.claude,
                now: now
            ) {
                sessions.append(session)
            }
        }

        sessions.append(contentsOf: openCodeSessions)
        sessions = deduplicate(sessions)
        sessions.sort(by: sessionSort)
        sessions = Array(sessions.prefix(24))
        sessions = attachGitContexts(to: sessions, now: now)

        return DashboardSnapshot(sessions: sessions, scannedAt: now)
    }

    private func recentFiles(
        in root: URL,
        modifiedAfter cutoff: Date,
        limit: Int
    ) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var files: [(URL, Date)] = []
        var inspected = 0

        for case let url as URL in enumerator {
            inspected += 1
            if inspected > 4_000 {
                break
            }
            guard url.pathExtension == "jsonl" else {
                continue
            }
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            ), values.isRegularFile == true else {
                continue
            }
            guard let date = values.contentModificationDate, date >= cutoff else {
                continue
            }
            files.append((url, date))
        }

        return files
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    private func modificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func deduplicate(_ sessions: [AgentSession]) -> [AgentSession] {
        var values: [String: AgentSession] = [:]
        for session in sessions {
            if let existing = values[session.id] {
                if session.lastActivityAt > existing.lastActivityAt {
                    values[session.id] = session
                }
            } else {
                values[session.id] = session
            }
        }
        return Array(values.values)
    }

    private func sessionSort(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.status.sortRank != rhs.status.sortRank {
            return lhs.status.sortRank < rhs.status.sortRank
        }
        return lhs.lastActivityAt > rhs.lastActivityAt
    }

    private func attachGitContexts(to sessions: [AgentSession], now: Date) -> [AgentSession] {
        var result = sessions
        var projectPaths = Set<String>()

        for index in result.indices {
            guard projectPaths.count < 10 else {
                break
            }
            let path = result[index].projectPath
            guard projectPaths.insert(path).inserted else {
                result[index].git = cachedGit(for: path, now: now)
                continue
            }
            result[index].git = cachedGit(for: path, now: now)
        }

        return result
    }

    private func cachedGit(for path: String, now: Date) -> GitContext? {
        cacheLock.lock()
        let cached = gitCache[path]
        cacheLock.unlock()

        if let cached, now.timeIntervalSince(cached.checkedAt) < (cached.value == nil ? 30 : 8) {
            return cached.value
        }

        let value = GitReader.read(projectPath: path)
        cacheLock.lock()
        gitCache[path] = GitCacheEntry(value: value, checkedAt: now)
        cacheLock.unlock()
        return value
    }
}
