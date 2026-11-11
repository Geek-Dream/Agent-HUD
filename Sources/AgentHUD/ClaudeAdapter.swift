import Foundation

enum ClaudeAdapter {
    static func parse(
        records: [[String: Any]],
        fileURL: URL,
        modifiedAt: Date,
        providerIsRunning: Bool,
        now: Date = .now
    ) -> AgentSession? {
        guard !records.isEmpty else {
            return nil
        }

        let sorted = records.sorted { eventDate($0) < eventDate($1) }
        let first = sorted.first ?? [:]
        let providerSessionID = JSONTools.string(first["sessionId"])
            ?? JSONTools.string(first["session_id"])
            ?? fileURL.deletingPathExtension().lastPathComponent

        var projectPath = JSONTools.string(first["cwd"])
        let startedAt = eventDate(first)
        var lastActivityAt = modifiedAt
        var aiTitle: String?
        var currentObjective: String?
        var currentActions: [String] = []
        var currentFiles: [String] = []
        var currentTool: String?
        var pendingTool = false
        var lastAssistantText: String?
        var lastAssistantAt: Date?
        var lastEventAt: Date?
        var latestErrorAt: Date?
        var runs: [TaskRun] = []
        var latestUserPrompt: UserPromptSnapshot?

        for record in sorted {
            let type = JSONTools.string(record["type"]) ?? ""
            let date = eventDate(record)
            lastEventAt = max(lastEventAt ?? .distantPast, date)
            lastActivityAt = max(lastActivityAt, date)

            if let cwd = JSONTools.string(record["cwd"]), cwd.hasPrefix("/") {
                projectPath = cwd
            }
            if type == "ai-title", let title = JSONTools.string(record["aiTitle"]) {
                aiTitle = title
            }

            let message = JSONTools.dictionary(record["message"])

            if type == "user" {
                let content = message?["content"]
                if isToolResult(content) {
                    pendingTool = false
                    continue
                }
                guard record["isMeta"] as? Bool != true else {
                    continue
                }

                let promptText = TextTools.userPromptText(
                    JSONTools.collectText(content).joined(separator: "\n")
                )
                let images = SessionAttachmentParser.claudeImages(from: content)
                guard !promptText.isEmpty || !images.isEmpty else {
                    continue
                }
                latestUserPrompt = UserPromptSnapshot(
                    text: promptText,
                    sentAt: date == .distantPast ? nil : date,
                    images: images
                )

                if let currentObjective,
                   let lastAssistantText,
                   let lastAssistantAt,
                   !runs.contains(where: { $0.objective == currentObjective && $0.completedAt == lastAssistantAt }) {
                    let completedRun = makeRun(
                        providerSessionID: providerSessionID,
                        index: runs.count,
                        objective: currentObjective,
                        summary: lastAssistantText,
                        actions: currentActions,
                        files: currentFiles,
                        completedAt: lastAssistantAt,
                        status: .completed
                    )
                    runs.append(completedRun)
                    currentActions = []
                    currentFiles = []
                }

                if let prompt = TextTools.meaningfulPrompt(promptText),
                   currentObjective == nil || !TextTools.isContinuationPrompt(prompt) {
                    currentObjective = prompt
                }
                lastAssistantText = nil
                lastAssistantAt = nil
                currentTool = nil
                pendingTool = false
            }

            if type == "assistant" {
                let parts = JSONTools.array(message?["content"]) ?? []

                for part in parts {
                    guard let part = JSONTools.dictionary(part) else { continue }
                    let partType = JSONTools.string(part["type"]) ?? ""

                    if partType == "text" {
                        let text = JSONTools.collectText(part["text"]).joined(separator: "\n")
                        if !TextTools.normalizedWhitespace(text).isEmpty {
                            lastAssistantText = text
                            lastAssistantAt = date
                            pendingTool = false
                        }
                    }

                    if partType == "tool_use" {
                        let toolName = JSONTools.string(part["name"]) ?? "tool"
                        currentTool = toolName
                        pendingTool = true
                        currentActions.append(toolName)
                        currentFiles.append(contentsOf: JSONTools.filePaths(from: part["input"]))
                    }
                }
            }

            if type == "error" || JSONTools.string(record["subtype"])?.lowercased() == "error" {
                latestErrorAt = date
            }
        }

        let age = max(0, now.timeIntervalSince(lastActivityAt))
        let isWaitingTool = ["askuserquestion", "request_user_input", "exitplanmode"]
            .contains(currentTool?.lowercased() ?? "")
        let status: AgentStatus
        let confidence: StatusConfidence

        if let latestErrorAt, latestErrorAt >= (lastAssistantAt ?? .distantPast) {
            status = .failed
            confidence = .medium
        } else if isWaitingTool && pendingTool {
            status = .waitingUser
            confidence = .medium
        } else if pendingTool {
            status = age < 240 ? .working : .idle
            confidence = .high
        } else if currentObjective != nil,
                  lastAssistantAt == nil || (lastEventAt ?? .distantPast) > (lastAssistantAt ?? .distantPast) {
            status = age < 180 ? .working : .idle
            confidence = .medium
        } else if let lastAssistantAt, lastAssistantText != nil {
            let completionAge = now.timeIntervalSince(lastAssistantAt)
            status = completionAge < 15 ? .working : .completed
            confidence = completionAge < 15 ? .medium : .high
        } else if age < 45 {
            status = .starting
            confidence = .low
        } else {
            status = .unknown
            confidence = .low
        }

        if status == .completed,
           let currentObjective,
           let lastAssistantText,
           let lastAssistantAt,
           !runs.contains(where: { $0.objective == currentObjective && $0.completedAt == lastAssistantAt }) {
            runs.append(makeRun(
                providerSessionID: providerSessionID,
                index: runs.count,
                objective: currentObjective,
                summary: lastAssistantText,
                actions: currentActions,
                files: currentFiles,
                completedAt: lastAssistantAt,
                status: .completed
            ))
        }

        let workingDirectory = projectPath ?? NSHomeDirectory()
        let projectName = URL(fileURLWithPath: workingDirectory).lastPathComponent
        let latestSubstantivePrompt: String?
        if let latestPrompt = latestUserPrompt?.text,
           let meaningfulPrompt = TextTools.meaningfulPrompt(latestPrompt),
           !TextTools.isContinuationPrompt(meaningfulPrompt) {
            latestSubstantivePrompt = meaningfulPrompt
        } else {
            latestSubstantivePrompt = nil
        }
        let titleSource = latestSubstantivePrompt
            ?? currentObjective
            ?? aiTitle
            ?? runs.last?.objective
            ?? projectName

        let action: String
        switch status {
        case .working:
            action = ActionDescription.describe(
                toolName: currentTool,
                detail: currentFiles.last.map { URL(fileURLWithPath: $0).lastPathComponent }
            )
        case .waitingUser:
            action = "Agent 正在等待确认或补充信息"
        case .completed:
            action = "本轮处理已完成，可查看总结"
        case .failed:
            action = "最近一轮处理出现错误"
        case .idle:
            action = "会话仍保留，等待下一次任务"
        case .starting:
            action = "已发现会话，正在读取进度"
        case .unknown:
            action = "等待更多本地信号"
        }

        return AgentSession(
            id: "claude:\(providerSessionID)",
            provider: .claude,
            providerSessionID: providerSessionID,
            projectName: projectName.isEmpty ? "未知项目" : projectName,
            projectPath: workingDirectory,
            title: TextTools.automaticTaskTitle(
                rawPrompt: titleSource,
                projectName: projectName,
                suggestedTitle: aiTitle
            ),
            titleSource: .automatic,
            status: status,
            confidence: confidence,
            currentAction: action,
            currentFiles: TextTools.unique(currentFiles),
            startedAt: min(startedAt, lastActivityAt),
            lastActivityAt: lastActivityAt,
            completedAt: status == .completed || status == .failed ? lastAssistantAt ?? lastActivityAt : nil,
            runs: Array(runs.suffix(12)),
            latestUserPrompt: latestUserPrompt,
            sourcePath: fileURL.path,
            isLive: providerIsRunning && age < 600,
            git: nil
        )
    }

    private static func makeRun(
        providerSessionID: String,
        index: Int,
        objective: String,
        summary: String,
        actions: [String],
        files: [String],
        completedAt: Date,
        status: AgentStatus
    ) -> TaskRun {
        TaskRun(
            id: "\(providerSessionID):run:\(index):\(Int(completedAt.timeIntervalSince1970))",
            objective: TextTools.titleLine(objective, limit: 180),
            summary: TextTools.sentence(summary, limit: 720),
            actions: Array(TextTools.unique(actions.map(ActionDescription.readableAction)).prefix(8)),
            filesChanged: Array(TextTools.unique(files).prefix(12)),
            completedAt: completedAt,
            status: status
        )
    }

    private static func isToolResult(_ content: Any?) -> Bool {
        guard let parts = content as? [Any] else {
            return false
        }
        return parts.contains { part in
            guard let dictionary = part as? [String: Any] else {
                return false
            }
            return dictionary["type"] as? String == "tool_result"
        }
    }

    private static func eventDate(_ record: [String: Any]) -> Date {
        DateParser.parse(record["timestamp"]) ?? .distantPast
    }
}
