import Foundation

enum CodexAdapter {
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

        let sorted = records.sorted { lhs, rhs in
            eventDate(lhs) < eventDate(rhs)
        }

        let metaRecord = sorted.first { $0["type"] as? String == "session_meta" }
        let metaPayload = JSONTools.dictionary(metaRecord?["payload"]) ?? [:]
        let providerSessionID = JSONTools.string(metaPayload["id"])
            ?? JSONTools.string(metaPayload["session_id"])
            ?? fileURL.deletingPathExtension().lastPathComponent

        var projectPath = JSONTools.string(metaPayload["cwd"])
        var startedAt = DateParser.parse(metaPayload["timestamp"])
            ?? eventDate(sorted.first ?? [:])
        var lastActivityAt = modifiedAt
        var currentObjective: String?
        var completedAt: Date?
        var latestErrorAt: Date?
        var currentTool: String?
        var currentActions: [String] = []
        var currentFiles: [String] = []
        var runs: [TaskRun] = []
        var latestUserPrompt: UserPromptSnapshot?
        var activeTurn = false
        var sawExplicitStart = false

        for record in sorted {
            let payload = JSONTools.dictionary(record["payload"]) ?? [:]
            let date = eventDate(record)
            let type = JSONTools.string(record["type"]) ?? ""
            let payloadType = JSONTools.string(payload["type"]) ?? ""

            if let cwd = JSONTools.string(payload["cwd"]), cwd.hasPrefix("/") {
                projectPath = cwd
            }

            if let start = DateParser.parse(payload["started_at"]), start < startedAt {
                startedAt = start
            }

            if date > lastActivityAt {
                lastActivityAt = date
            }

            if type == "response_item", payloadType == "message" {
                let role = JSONTools.string(payload["role"]) ?? ""
                if role == "user",
                   let snapshot = makePromptSnapshot(
                       text: JSONTools.collectText(payload["content"]).joined(separator: "\n"),
                       content: payload["content"],
                       sentAt: date
                   ) {
                    latestUserPrompt = snapshot
                    if let prompt = TextTools.meaningfulPrompt(snapshot.text),
                       currentObjective == nil || !TextTools.isContinuationPrompt(prompt) {
                        currentObjective = prompt
                    }
                    activeTurn = true
                }
            }

            if type == "event_msg",
               let item = JSONTools.dictionary(payload["item"]),
               (payloadType.lowercased() == "user_message"
                   || (JSONTools.string(item["type"]) ?? "").lowercased() == "usermessage"),
               let snapshot = makePromptSnapshot(
                   text: JSONTools.collectText(item["content"]).joined(separator: "\n"),
                   content: item["content"],
                   sentAt: date
               ) {
                latestUserPrompt = snapshot
                if let prompt = TextTools.meaningfulPrompt(snapshot.text),
                   currentObjective == nil || !TextTools.isContinuationPrompt(prompt) {
                    currentObjective = prompt
                }
                activeTurn = true
            }

            if type == "response_item", payloadType == "function_call" {
                let tool = JSONTools.string(payload["name"]) ?? "tool"
                currentTool = tool
                activeTurn = true
                sawExplicitStart = true
                currentActions.append(tool)

                let arguments = parseArguments(payload["arguments"])
                currentFiles.append(contentsOf: JSONTools.filePaths(from: arguments))

                if let command = commandDetail(from: arguments) {
                    currentActions.append(command)
                }
            }

            if type == "event_msg", payloadType == "task_started" {
                activeTurn = true
                sawExplicitStart = true
                currentTool = nil
            }

            if type == "event_msg", payloadType == "item_completed" {
                if let item = JSONTools.dictionary(payload["item"]) {
                    let itemType = JSONTools.string(item["type"]) ?? ""
                    if itemType == "command_execution" || itemType == "command" {
                        if let command = JSONTools.string(item["command"]) {
                            currentActions.append(command)
                        }
                    }
                    if let tool = JSONTools.string(item["name"]) {
                        currentTool = tool
                    }
                    currentFiles.append(contentsOf: JSONTools.filePaths(from: item))
                }
            }

            if type == "event_msg", payloadType == "task_complete" {
                let summary = JSONTools.string(payload["last_agent_message"])
                    ?? "本轮任务完成，没有可提取的完成说明。"
                let objective = currentObjective ?? "未记录任务目标"
                let completionDate = DateParser.parse(payload["completed_at"]) ?? date
                let run = makeRun(
                    providerSessionID: providerSessionID,
                    index: runs.count,
                    objective: objective,
                    summary: summary,
                    actions: currentActions,
                    files: currentFiles,
                    completedAt: completionDate,
                    status: .completed
                )
                runs.append(run)
                completedAt = completionDate
                activeTurn = false
                currentTool = nil
                currentActions = []
                currentFiles = []
            }

            if payloadType.lowercased().contains("error")
                || (type.lowercased().contains("error") && payloadType != "item_completed") {
                latestErrorAt = date
                activeTurn = false
            }
        }

        let age = max(0, now.timeIntervalSince(lastActivityAt))
        let status: AgentStatus
        let confidence: StatusConfidence

        if let latestErrorAt, latestErrorAt >= (completedAt ?? .distantPast) {
            status = .failed
            confidence = .high
        } else if activeTurn {
            status = age < 180 ? .working : .idle
            confidence = sawExplicitStart || currentTool != nil ? .high : .medium
        } else if completedAt != nil {
            status = .completed
            confidence = .high
        } else if age < 45 {
            status = .starting
            confidence = .medium
        } else {
            status = .unknown
            confidence = .low
        }

        let fallbackTitle = fileURL.deletingPathExtension().lastPathComponent
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
            ?? runs.last?.objective
            ?? JSONTools.string(metaPayload["thread_source"])
            ?? fallbackTitle
        let title = TextTools.automaticTaskTitle(
            rawPrompt: titleSource,
            projectName: URL(fileURLWithPath: projectPath ?? NSHomeDirectory()).lastPathComponent
        )
        let action = currentAction(
            status: status,
            tool: currentTool,
            file: currentFiles.last
        )

        let workingDirectory = projectPath ?? NSHomeDirectory()
        let projectName = URL(fileURLWithPath: workingDirectory).lastPathComponent

        return AgentSession(
            id: "codex:\(providerSessionID)",
            provider: .codex,
            providerSessionID: providerSessionID,
            projectName: projectName.isEmpty ? "未知项目" : projectName,
            projectPath: workingDirectory,
            title: title,
            titleSource: .automatic,
            status: status,
            confidence: confidence,
            currentAction: action,
            currentFiles: TextTools.unique(currentFiles),
            startedAt: min(startedAt, lastActivityAt),
            lastActivityAt: lastActivityAt,
            completedAt: status == .completed || status == .failed ? completedAt ?? lastActivityAt : nil,
            runs: Array(runs.suffix(12)),
            latestUserPrompt: latestUserPrompt,
            sourcePath: fileURL.path,
            isLive: providerIsRunning && age < 600,
            git: nil
        )
    }

    private static func makePromptSnapshot(
        text: String,
        content: Any?,
        sentAt: Date
    ) -> UserPromptSnapshot? {
        let promptText = TextTools.userPromptText(text)
        let images = SessionAttachmentParser.codexImages(from: content)
        guard !promptText.isEmpty || !images.isEmpty else {
            return nil
        }
        return UserPromptSnapshot(
            text: promptText,
            sentAt: sentAt == .distantPast ? nil : sentAt,
            images: images
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
            summary: TextTools.sentence(summary, limit: 640),
            actions: TextTools.unique(actions.map(ActionDescription.readableAction)).prefix(8).map { $0 },
            filesChanged: TextTools.unique(files).prefix(12).map { $0 },
            completedAt: completedAt,
            status: status
        )
    }

    private static func eventDate(_ record: [String: Any]) -> Date {
        let payload = JSONTools.dictionary(record["payload"]) ?? [:]
        return DateParser.parse(record["timestamp"])
            ?? DateParser.parse(payload["started_at"])
            ?? DateParser.parse(payload["completed_at"])
            ?? DateParser.parse(payload["started_at_ms"])
            ?? DateParser.parse(payload["completed_at_ms"])
            ?? .distantPast
    }

    private static func parseArguments(_ value: Any?) -> Any? {
        if let dictionary = value as? [String: Any] {
            return dictionary
        }
        if let string = value as? String,
           let data = string.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            return object
        }
        return value
    }

    private static func commandDetail(from value: Any?) -> String? {
        guard let dictionary = value as? [String: Any] else {
            return nil
        }
        if let command = dictionary["cmd"] as? String {
            return command
        }
        if let command = dictionary["command"] as? String {
            return command
        }
        return nil
    }

    private static func currentAction(status: AgentStatus, tool: String?, file: String?) -> String {
        switch status {
        case .working:
            return ActionDescription.describe(
                toolName: tool,
                detail: file.map { URL(fileURLWithPath: $0).lastPathComponent }
            )
        case .idle:
            return "会话仍保留，等待下一次任务"
        case .completed:
            return "最近一轮处理已完成"
        case .failed:
            return "最近一轮处理出现错误"
        case .starting:
            return "已发现会话，正在读取进度"
        case .waitingUser, .unknown:
            return "正在等待更多本地信号"
        }
    }
}
