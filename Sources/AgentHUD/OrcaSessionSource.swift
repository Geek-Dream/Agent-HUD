import Foundation
import SQLite3

enum OrcaSessionSource {
    static func scan(now: Date = .now) -> [AgentSession]? {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
        guard let applicationSupport else {
            return nil
        }

        let orcaRoot = applicationSupport.appendingPathComponent("orca", isDirectory: true)
        let profileDatabase = orcaRoot
            .appendingPathComponent("profiles/local-default/profile-state.db")
        let statusDatabase = orcaRoot
            .appendingPathComponent("agent-hooks/last-status.db")

        guard let workspaceJSON = firstDatabaseValue(
            at: profileDatabase,
            sql: "SELECT payload FROM profile_state_documents WHERE domain = 'workspaceSession' LIMIT 1"
        ), let workspacePayload = jsonObject(workspaceJSON) else {
            return nil
        }

        let uiPayload = firstDatabaseValue(
            at: profileDatabase,
            sql: "SELECT payload FROM profile_state_documents WHERE domain = 'ui' LIMIT 1"
        ).flatMap(jsonObject)
        let worktreeMeta = firstDatabaseValue(
            at: profileDatabase,
            sql: "SELECT payload FROM profile_state_documents WHERE domain = 'worktreeMeta' LIMIT 1"
        ).flatMap(jsonObject) ?? [:]
        let statusValues = databaseValues(
            at: statusDatabase,
            sql: "SELECT value FROM rows WHERE substr(key, 1, 5) = 'entry'"
        ) ?? []
        let statusEntries = statusValues.compactMap(jsonObject)

        return makeSessions(
            workspacePayload: workspacePayload,
            statusEntries: statusEntries,
            uiPayload: uiPayload,
            worktreeMeta: worktreeMeta,
            now: now
        )
    }

    static func makeSessions(
        workspacePayload: [String: Any],
        statusEntries: [[String: Any]],
        uiPayload: [String: Any]? = nil,
        worktreeMeta: [String: Any] = [:],
        now: Date
    ) -> [AgentSession]? {
        guard let tabsByWorktree = JSONTools.dictionary(
            workspacePayload["tabsByWorktree"]
        ) else {
            return nil
        }

        let unifiedTabs = unifiedTabsByID(workspacePayload["unifiedTabs"])
        let sleepingSessions = JSONTools.dictionary(
            workspacePayload["sleepingAgentSessionsByPaneKey"]
        ) ?? [:]
        let collapsedProjects = collapsedProjectKeys(uiPayload)
        var sessionsByID: [String: AgentSession] = [:]

        for (worktreeKey, value) in tabsByWorktree {
            if isCollapsedProject(
                worktreeKey: worktreeKey,
                worktreeMeta: worktreeMeta,
                collapsedProjects: collapsedProjects
            ) {
                continue
            }

            guard let tabs = JSONTools.array(value) else {
                continue
            }

            for value in tabs {
                guard let tab = JSONTools.dictionary(value),
                      let aiTitle = JSONTools.dictionary(tab["aiVaultTitle"]),
                      let provider = provider(from: JSONTools.string(aiTitle["agent"])),
                      let providerSessionID = JSONTools.string(aiTitle["sessionId"]),
                      let tabID = JSONTools.string(tab["id"]) else {
                    continue
                }

                let unifiedTab = unifiedTabs[tabID]
                let status = bestStatus(
                    tabID: tabID,
                    providerSessionID: providerSessionID,
                    entries: statusEntries
                )
                let sleeping = bestSleepingSession(
                    tabID: tabID,
                    providerSessionID: providerSessionID,
                    entries: sleepingSessions
                )

                let session = makeSession(
                    provider: provider,
                    providerSessionID: providerSessionID,
                    tabID: tabID,
                    tab: tab,
                    unifiedTab: unifiedTab,
                    worktreeKey: worktreeKey,
                    statusEntry: status,
                    sleepingEntry: sleeping,
                    now: now
                )

                if let existing = sessionsByID[session.id] {
                    if session.lastActivityAt > existing.lastActivityAt {
                        sessionsByID[session.id] = session
                    }
                } else {
                    sessionsByID[session.id] = session
                }
            }
        }

        return Array(sessionsByID.values)
    }

    private static func makeSession(
        provider: AgentProvider,
        providerSessionID: String,
        tabID: String,
        tab: [String: Any],
        unifiedTab: [String: Any]?,
        worktreeKey: String,
        statusEntry: [String: Any]?,
        sleepingEntry: [String: Any]?,
        now: Date
    ) -> AgentSession {
        let statusPayload = JSONTools.dictionary(statusEntry?["payload"]) ?? [:]
        let providerSession = JSONTools.dictionary(statusEntry?["providerSession"]) ?? [:]
        let transcriptPath = JSONTools.string(providerSession["transcriptPath"])
        let adapterSession = transcriptSession(
            provider: provider,
            transcriptPath: transcriptPath,
            now: now
        )

        let mainAgent = JSONTools.dictionary(statusPayload["mainAgent"])
            ?? JSONTools.dictionary(statusEntry?["mainAgent"])
            ?? [:]
        let sleepingPayload = JSONTools.dictionary(sleepingEntry?["mainAgent"])
            ?? JSONTools.dictionary(sleepingEntry?["payload"])
            ?? [:]

        let rawState = JSONTools.string(mainAgent["state"])
            ?? JSONTools.string(statusPayload["state"])
            ?? JSONTools.string(sleepingPayload["state"])
            ?? JSONTools.string(sleepingEntry?["state"])
        let outcome = JSONTools.string(mainAgent["outcome"])
            ?? JSONTools.string(statusPayload["outcome"])
            ?? JSONTools.string(statusEntry?["turnEndDisposition"])
        let status = rawState.map { mapStatus($0, outcome: outcome) }
            ?? adapterSession?.status
            ?? .unknown
        let confidence: StatusConfidence = rawState == nil
            ? adapterSession?.confidence ?? .low
            : .high

        let tabPath = worktreePath(from: worktreeKey)
        let projectPath = JSONTools.string(providerSession["cwd"])
            ?? adapterSession?.projectPath
            ?? tabPath
            ?? NSHomeDirectory()
        let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
        let statusPrompt = JSONTools.string(statusPayload["prompt"])
        let rawTitleSource = [
            adapterSession?.latestUserPrompt?.text,
            statusPrompt,
            adapterSession?.title
        ]
            .compactMap { value in
                value.flatMap(TextTools.meaningfulPrompt)
            }
            .first { !TextTools.isContinuationPrompt($0) }
        let title = TextTools.automaticTaskTitle(
            rawPrompt: rawTitleSource,
            projectName: projectName
        )

        let tabStartedAt = DateParser.parse(tab["createdAt"])
        let stateStartedAt = DateParser.parse(mainAgent["stateStartedAt"])
            ?? DateParser.parse(statusEntry?["stateStartedAt"])
            ?? DateParser.parse(statusEntry?["turnStartedAt"])
        let receivedAt = DateParser.parse(statusEntry?["receivedAt"])
            ?? DateParser.parse(statusEntry?["capturedAt"])
            ?? DateParser.parse(statusEntry?["updatedAt"])
        let sleepingAt = DateParser.parse(sleepingEntry?["updatedAt"])
            ?? DateParser.parse(sleepingEntry?["capturedAt"])
        let startedAt = [
            tabStartedAt,
            adapterSession?.startedAt,
            stateStartedAt
        ].compactMap { $0 }.min() ?? now
        let lastActivityAt = [
            receivedAt,
            sleepingAt,
            stateStartedAt,
            adapterSession?.lastActivityAt,
            tabStartedAt
        ].compactMap { $0 }.max() ?? now

        let completedAt: Date?
        if status == .completed || status == .failed {
            completedAt = DateParser.parse(statusPayload["turnCompletedAt"])
                ?? DateParser.parse(mainAgent["stateStartedAt"])
                ?? receivedAt
                ?? adapterSession?.completedAt
        } else {
            completedAt = nil
        }

        var runs = adapterSession?.runs ?? []
        if runs.isEmpty,
           let summary = JSONTools.string(statusPayload["lastAssistantMessage"]),
           !TextTools.normalizedWhitespace(summary).isEmpty,
           let completedAt {
            let objective = JSONTools.string(statusPayload["prompt"])
                .flatMap(TextTools.meaningfulPrompt)
                ?? title
            runs = [TaskRun(
                id: "\(provider.rawValue):\(providerSessionID):orca:\(Int(completedAt.timeIntervalSince1970))",
                objective: TextTools.automaticTaskTitle(
                    rawPrompt: objective,
                    projectName: projectName,
                    limit: 72
                ),
                summary: TextTools.sentence(summary, limit: 720),
                actions: [],
                filesChanged: [],
                completedAt: completedAt,
                status: status
            )]
        }

        let toolInput = parseJSON(statusPayload["toolInput"])
        let statusFiles = JSONTools.filePaths(from: toolInput)
        let currentFiles = TextTools.unique((adapterSession?.currentFiles ?? []) + statusFiles)
        let action = currentAction(
            status: status,
            payload: statusPayload,
            fallback: adapterSession?.currentAction
        )
        let latestUserPrompt: UserPromptSnapshot?
        if let adapterPrompt = adapterSession?.latestUserPrompt {
            latestUserPrompt = adapterPrompt
        } else if let statusPrompt {
            let promptText = TextTools.userPromptText(statusPrompt)
            latestUserPrompt = promptText.isEmpty
                ? nil
                : UserPromptSnapshot(
                    text: promptText,
                    sentAt: receivedAt ?? stateStartedAt,
                    images: []
                )
        } else {
            latestUserPrompt = nil
        }

        return AgentSession(
            id: "\(provider.rawValue):\(providerSessionID)",
            provider: provider,
            providerSessionID: providerSessionID,
            projectName: projectName.isEmpty ? "未知项目" : projectName,
            projectPath: projectPath,
            title: title,
            titleSource: .automatic,
            status: status,
            confidence: confidence,
            currentAction: action,
            currentFiles: currentFiles,
            startedAt: min(startedAt, lastActivityAt),
            lastActivityAt: lastActivityAt,
            completedAt: completedAt,
            runs: Array(runs.suffix(12)),
            latestUserPrompt: latestUserPrompt,
            sourcePath: transcriptPath ?? "",
            isLive: true,
            git: nil
        )
    }

    private static func transcriptSession(
        provider: AgentProvider,
        transcriptPath: String?,
        now: Date
    ) -> AgentSession? {
        guard let transcriptPath, !transcriptPath.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: transcriptPath)
        guard FileManager.default.fileExists(atPath: url.path),
              let records = try? LogFileReader.readJSONLines(from: url),
              let modifiedAt = try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
              ).contentModificationDate else {
            return nil
        }

        switch provider {
        case .codex:
            return CodexAdapter.parse(
                records: records,
                fileURL: url,
                modifiedAt: modifiedAt,
                providerIsRunning: true,
                now: now
            )
        case .claude:
            return ClaudeAdapter.parse(
                records: records,
                fileURL: url,
                modifiedAt: modifiedAt,
                providerIsRunning: true,
                now: now
            )
        case .pi:
            return nil
        case .opencode:
            return nil
        }
    }

    private static func bestStatus(
        tabID: String,
        providerSessionID: String,
        entries: [[String: Any]]
    ) -> [String: Any]? {
        entries.compactMap { entry -> ([String: Any], Date)? in
            let providerSession = JSONTools.dictionary(entry["providerSession"])
            let tabMatches = JSONTools.string(entry["tabId"]) == tabID
            let sessionMatches = JSONTools.string(providerSession?["id"]) == providerSessionID
            let paneMatches = JSONTools.string(entry["paneKey"])?.hasPrefix("\(tabID):") == true
            guard tabMatches || sessionMatches || paneMatches else {
                return nil
            }

            let date = DateParser.parse(entry["receivedAt"])
                ?? DateParser.parse(entry["capturedAt"])
                ?? DateParser.parse(entry["updatedAt"])
                ?? .distantPast
            return (entry, date)
        }.max { $0.1 < $1.1 }?.0
    }

    private static func bestSleepingSession(
        tabID: String,
        providerSessionID: String,
        entries: [String: Any]
    ) -> [String: Any]? {
        entries.values.compactMap { value -> ([String: Any], Date)? in
            guard let entry = JSONTools.dictionary(value) else {
                return nil
            }
            let providerSession = JSONTools.dictionary(entry["providerSession"])
            let tabMatches = JSONTools.string(entry["tabId"]) == tabID
            let sessionMatches = JSONTools.string(providerSession?["id"]) == providerSessionID
            let paneMatches = JSONTools.string(entry["paneKey"])?.hasPrefix("\(tabID):") == true
            guard tabMatches || sessionMatches || paneMatches else {
                return nil
            }

            let date = DateParser.parse(entry["updatedAt"])
                ?? DateParser.parse(entry["capturedAt"])
                ?? .distantPast
            return (entry, date)
        }.max { $0.1 < $1.1 }?.0
    }

    private static func currentAction(
        status: AgentStatus,
        payload: [String: Any],
        fallback: String?
    ) -> String {
        switch status {
        case .working:
            if JSONTools.string(payload["workingMode"])?.lowercased() == "monitoring" {
                return "Agent 正在监控任务进度"
            }
            let toolName = JSONTools.string(payload["toolName"])
            let toolInput = parseJSON(payload["toolInput"])
            let detail = JSONTools.filePaths(from: toolInput).last.map {
                URL(fileURLWithPath: $0).lastPathComponent
            }
            return ActionDescription.describe(toolName: toolName, detail: detail)
        case .waitingUser:
            return "Agent 正在等待确认或补充信息"
        case .completed:
            return "本轮处理已完成，可查看总结"
        case .failed:
            return "最近一轮处理出现错误"
        case .idle:
            return "会话仍保留，等待下一次任务"
        case .starting:
            return "已发现会话，正在读取进度"
        case .unknown:
            return fallback ?? "等待更多本地信号"
        }
    }

    private static func mapStatus(_ rawState: String, outcome: String?) -> AgentStatus {
        switch rawState.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "working", "monitoring", "running":
            return .working
        case "waiting", "blocked", "permission":
            return .waitingUser
        case "done", "completed":
            let normalizedOutcome = outcome?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if ["failure", "failed", "interruption", "cancellation", "cancelled", "unconfirmed", "error"]
                .contains(normalizedOutcome ?? "") {
                return .failed
            }
            return .completed
        case "failed", "failure", "error":
            return .failed
        case "idle", "ready":
            return .idle
        case "starting", "start":
            return .starting
        default:
            return .unknown
        }
    }

    private static func provider(from rawValue: String?) -> AgentProvider? {
        switch rawValue?.lowercased() {
        case "codex", "openai-codex":
            return .codex
        case "claude", "claude-code":
            return .claude
        case "pi", "pi-agent":
            return .pi
        case "opencode", "open-code":
            return .opencode
        default:
            return nil
        }
    }

    private static func unifiedTabsByID(_ value: Any?) -> [String: [String: Any]] {
        guard let groups = JSONTools.dictionary(value) else {
            return [:]
        }

        var result: [String: [String: Any]] = [:]
        for tabs in groups.values {
            for value in JSONTools.array(tabs) ?? [] {
                guard let tab = JSONTools.dictionary(value),
                      let id = JSONTools.string(tab["id"]) else {
                    continue
                }
                result[id] = tab
            }
        }
        return result
    }

    private static func worktreePath(from key: String) -> String? {
        guard let separator = key.range(of: "::") else {
            return nil
        }
        let path = String(key[separator.upperBound...])
        return path.hasPrefix("/") ? path : nil
    }

    private static func collapsedProjectKeys(_ uiPayload: [String: Any]?) -> Set<String> {
        guard let values = JSONTools.array(uiPayload?["collapsedGroups"]) else {
            return []
        }
        return Set(values.compactMap { value in
            guard let key = value as? String,
                  key.hasPrefix("project:") else {
                return nil
            }
            return key.lowercased()
        })
    }

    private static func isCollapsedProject(
        worktreeKey: String,
        worktreeMeta: [String: Any],
        collapsedProjects: Set<String>
    ) -> Bool {
        guard !collapsedProjects.isEmpty,
              let meta = JSONTools.dictionary(worktreeMeta[worktreeKey]),
              let projectID = JSONTools.string(meta["projectId"]) else {
            return false
        }
        return collapsedProjects.contains("project:\(projectID.lowercased())")
    }

    private static func parseJSON(_ value: Any?) -> Any? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        guard let string = value as? String,
              let data = string.data(using: .utf8) else {
            return value
        }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func jsonObject(_ string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return object as? [String: Any]
    }

    private static func firstDatabaseValue(at url: URL, sql: String) -> String? {
        databaseValues(at: url, sql: sql)?.first
    }

    private static func databaseValues(at url: URL, sql: String) -> [String]? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var values: [String] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return values
            }
            guard result == SQLITE_ROW,
                  let text = sqlite3_column_text(statement, 0) else {
                return nil
            }
            values.append(String(cString: text))
        }
    }
}
