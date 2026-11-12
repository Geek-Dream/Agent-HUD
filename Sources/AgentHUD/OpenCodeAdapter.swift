import Foundation

struct OpenCodeEvent {
    let id: String
    let date: Date
    let data: [String: Any]
    var messageID: String? = nil
}

struct OpenCodeSessionRecord {
    let id: String
    let directory: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let messages: [OpenCodeEvent]
    let parts: [OpenCodeEvent]
}

enum OpenCodeAdapter {
    static func parse(
        record: OpenCodeSessionRecord,
        fileURL: URL,
        providerIsRunning: Bool,
        now: Date = .now
    ) -> AgentSession? {
        let partsByMessage = Dictionary(
            grouping: record.parts,
            by: { $0.messageID ?? JSONTools.string($0.data["messageID"]) ?? "" }
        )
        let messages = record.messages.sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
        }

        var currentObjective: String?
        var currentActions: [String] = []
        var currentFiles: [String] = []
        var currentTool: String?
        var pendingTool = false
        var lastAssistantText: String?
        var lastAssistantAt: Date?
        var latestUserAt: Date?
        var latestErrorAt: Date?
        var latestPrompt: UserPromptSnapshot?
        var runs: [TaskRun] = []
        var lastActivityAt = record.updatedAt

        for message in messages {
            lastActivityAt = max(lastActivityAt, message.date)
            let role = JSONTools.string(message.data["role"]) ?? ""
            let messageParts = (partsByMessage[message.id] ?? []).sorted { lhs, rhs in
                lhs.date == rhs.date ? lhs.id < rhs.id : lhs.date < rhs.date
            }

            if role == "user" {
                let text = messageParts.compactMap { part -> String? in
                    guard JSONTools.string(part.data["type"]) == "text" else {
                        return nil
                    }
                    return JSONTools.string(part.data["text"])
                }.joined(separator: "\n")
                let promptText = TextTools.userPromptText(text)
                guard !promptText.isEmpty else {
                    continue
                }

                latestPrompt = UserPromptSnapshot(
                    text: promptText,
                    sentAt: message.date,
                    images: []
                )
                latestUserAt = message.date
                latestErrorAt = nil
                pendingTool = false
                currentTool = nil

                if let currentObjective,
                   let lastAssistantText,
                   let lastAssistantAt,
                   !runs.contains(where: {
                       $0.objective == currentObjective && $0.completedAt == lastAssistantAt
                   }) {
                    runs.append(makeRun(
                        sessionID: record.id,
                        index: runs.count,
                        objective: currentObjective,
                        summary: lastAssistantText,
                        actions: currentActions,
                        files: currentFiles,
                        completedAt: lastAssistantAt,
                        status: .completed
                    ))
                    currentActions = []
                    currentFiles = []
                }

                if let prompt = TextTools.meaningfulPrompt(promptText),
                   currentObjective == nil || !TextTools.isContinuationPrompt(prompt) {
                    currentObjective = prompt
                }
                lastAssistantText = nil
                lastAssistantAt = nil
                continue
            }

            guard role == "assistant" else {
                continue
            }

            for part in messageParts {
                lastActivityAt = max(lastActivityAt, part.date)
                let type = JSONTools.string(part.data["type"]) ?? ""

                if type == "text",
                   let text = JSONTools.string(part.data["text"]),
                   !TextTools.normalizedWhitespace(text).isEmpty {
                    lastAssistantText = text
                    lastAssistantAt = nestedDate(part.data, keys: ["end"])
                        ?? nestedDate(message.data, keys: ["completed"])
                        ?? part.date
                }

                if type == "patch" {
                    currentFiles.append(contentsOf: stringArray(part.data["files"]))
                }

                guard type == "tool" else {
                    continue
                }

                let tool = JSONTools.string(part.data["tool"]) ?? "tool"
                let state = JSONTools.dictionary(part.data["state"]) ?? [:]
                let input = JSONTools.dictionary(state["input"])
                let toolStatus = JSONTools.string(state["status"])?.lowercased() ?? ""
                currentTool = tool
                currentActions.append(tool)
                if let command = JSONTools.string(input?["command"]) {
                    currentActions.append(command)
                }
                currentFiles.append(contentsOf: JSONTools.filePaths(from: input))
                for key in ["filePath", "path", "file", "file_path"] {
                    if let path = JSONTools.string(input?[key]) {
                        currentFiles.append(path)
                    }
                }
                currentFiles.append(contentsOf: JSONTools.filePaths(from: part.data["files"]))

                switch toolStatus {
                case "running", "pending", "waiting", "waiting_user", "waitinguser":
                    pendingTool = true
                case "error", "failed", "failure":
                    pendingTool = false
                    latestErrorAt = part.date
                default:
                    pendingTool = false
                }
            }

            if lastAssistantAt == nil,
               let completed = nestedDate(message.data, keys: ["completed"]) {
                lastAssistantAt = completed
            }
        }

        let age = max(0, now.timeIntervalSince(lastActivityAt))
        let waitingTools = ["question", "askuserquestion", "request_user_input", "exitplanmode"]
        let status: AgentStatus
        let confidence: StatusConfidence

        if latestErrorAt != nil {
            status = .failed
            confidence = .high
        } else if pendingTool,
                  waitingTools.contains(currentTool?.lowercased() ?? "") {
            status = .waitingUser
            confidence = .high
        } else if pendingTool {
            status = age < 240 ? .working : .idle
            confidence = .high
        } else if currentObjective != nil,
                  lastAssistantAt == nil || (latestUserAt ?? .distantPast) > (lastAssistantAt ?? .distantPast) {
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
           !runs.contains(where: {
               $0.objective == currentObjective && $0.completedAt == lastAssistantAt
           }) {
            runs.append(makeRun(
                sessionID: record.id,
                index: runs.count,
                objective: currentObjective,
                summary: lastAssistantText,
                actions: currentActions,
                files: currentFiles,
                completedAt: lastAssistantAt,
                status: .completed
            ))
        }

        let projectName = URL(fileURLWithPath: record.directory).lastPathComponent
        let latestSubstantive: String?
        if let text = latestPrompt?.text {
            latestSubstantive = TextTools.meaningfulPrompt(text)
                .flatMap { TextTools.isContinuationPrompt($0) ? nil : $0 }
        } else {
            latestSubstantive = nil
        }
        let titleSource = latestSubstantive ?? currentObjective ?? record.title

        return AgentSession(
            id: "opencode:\(record.id)",
            provider: .opencode,
            providerSessionID: record.id,
            projectName: projectName.isEmpty ? "未知项目" : projectName,
            projectPath: record.directory,
            title: TextTools.automaticTaskTitle(
                rawPrompt: titleSource,
                projectName: projectName,
                suggestedTitle: record.title
            ),
            titleSource: .automatic,
            status: status,
            confidence: confidence,
            currentAction: action(for: status, tool: currentTool, file: currentFiles.last),
            currentFiles: TextTools.unique(currentFiles),
            startedAt: min(record.createdAt, lastActivityAt),
            lastActivityAt: lastActivityAt,
            completedAt: status == .completed || status == .failed
                ? lastAssistantAt ?? lastActivityAt
                : nil,
            runs: Array(runs.suffix(12)),
            latestUserPrompt: latestPrompt,
            sourcePath: fileURL.path,
            isLive: providerIsRunning && age < 600,
            git: nil
        )
    }

    private static func nestedDate(_ value: [String: Any], keys: [String]) -> Date? {
        let time = JSONTools.dictionary(value["time"]) ?? [:]
        for key in keys {
            if let date = DateParser.parse(time[key]) {
                return date
            }
        }
        return nil
    }

    private static func stringArray(_ value: Any?) -> [String] {
        JSONTools.array(value)?.compactMap { $0 as? String } ?? []
    }

    private static func makeRun(
        sessionID: String,
        index: Int,
        objective: String,
        summary: String,
        actions: [String],
        files: [String],
        completedAt: Date,
        status: AgentStatus
    ) -> TaskRun {
        TaskRun(
            id: "\(sessionID):run:\(index):\(Int(completedAt.timeIntervalSince1970))",
            objective: TextTools.titleLine(objective, limit: 180),
            summary: TextTools.sentence(summary, limit: 720),
            actions: Array(TextTools.unique(actions.map(ActionDescription.readableAction)).prefix(8)),
            filesChanged: Array(TextTools.unique(files).prefix(12)),
            completedAt: completedAt,
            status: status
        )
    }

    private static func action(for status: AgentStatus, tool: String?, file: String?) -> String {
        switch status {
        case .working:
            return ActionDescription.describe(
                toolName: tool,
                detail: file.map { URL(fileURLWithPath: $0).lastPathComponent }
            )
        case .waitingUser:
            return "OpenCode 正在等待确认或补充信息"
        case .completed:
            return "本轮处理已完成，可查看总结"
        case .failed:
            return "最近一轮处理出现错误"
        case .idle:
            return "会话仍保留，等待下一次任务"
        case .starting:
            return "已发现 OpenCode 会话，正在读取进度"
        case .unknown:
            return "等待更多本地信号"
        }
    }
}
