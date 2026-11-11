using System.Text.Json;

namespace AgentHUD.Core;

public static class ClaudeAdapter
{
    public static AgentSession? Parse(
        IReadOnlyList<JsonElement> records,
        string filePath,
        DateTimeOffset modifiedAt,
        bool providerIsRunning,
        DateTimeOffset now)
    {
        if (records.Count == 0)
        {
            return null;
        }

        var sorted = records.OrderBy(EventDate).ToArray();
        var first = sorted[0];
        var providerSessionId = JsonTools.String(first, "sessionId")
            ?? JsonTools.String(first, "session_id")
            ?? Path.GetFileNameWithoutExtension(filePath);
        var projectPath = JsonTools.String(first, "cwd");
        var startedAt = EventDate(first);
        var lastActivityAt = modifiedAt;
        string? aiTitle = null;
        string? currentObjective = null;
        var currentActions = new List<string>();
        var currentFiles = new List<string>();
        string? currentTool = null;
        var pendingTool = false;
        string? lastAssistantText = null;
        DateTimeOffset? lastAssistantAt = null;
        DateTimeOffset? lastEventAt = null;
        DateTimeOffset? latestErrorAt = null;
        var runs = new List<TaskRun>();
        UserPromptSnapshot? latestPrompt = null;

        foreach (var record in sorted)
        {
            var type = JsonTools.String(record, "type") ?? string.Empty;
            var date = EventDate(record);
            if (date > (lastEventAt ?? DateTimeOffset.MinValue))
            {
                lastEventAt = date;
            }
            if (date > lastActivityAt)
            {
                lastActivityAt = date;
            }

            var cwd = JsonTools.String(record, "cwd");
            if (!string.IsNullOrWhiteSpace(cwd) && Path.IsPathRooted(cwd))
            {
                projectPath = cwd;
            }
            if (type == "ai-title")
            {
                aiTitle = JsonTools.String(record, "aiTitle") ?? aiTitle;
            }

            var message = JsonTools.Object(record, "message");
            if (type == "user")
            {
                var content = message is null ? null : JsonTools.Array(message.Value, "content");
                if (IsToolResult(content))
                {
                    pendingTool = false;
                    continue;
                }
                if (JsonTools.Bool(record, "isMeta") == true)
                {
                    continue;
                }

                var latestPromptText = TextTools.UserPromptText(
                    string.Join("\n", JsonTools.CollectText(content)));
                var images = SessionAttachmentParser.ClaudeImages(content);
                if (string.IsNullOrWhiteSpace(latestPromptText) && images.Count == 0)
                {
                    continue;
                }

                latestPrompt = new UserPromptSnapshot(
                    latestPromptText,
                    date == DateTimeOffset.MinValue ? null : date,
                    images);

                if (currentObjective is not null
                    && lastAssistantText is not null
                    && lastAssistantAt is not null
                    && !runs.Any(run => run.Objective == currentObjective
                        && run.CompletedAt == lastAssistantAt))
                {
                    runs.Add(MakeRun(
                        providerSessionId,
                        runs.Count,
                        currentObjective,
                        lastAssistantText,
                        currentActions,
                        currentFiles,
                        lastAssistantAt.Value));
                    currentActions.Clear();
                    currentFiles.Clear();
                }

                var candidateObjective = TextTools.MeaningfulPrompt(latestPromptText);
                if (candidateObjective is not null
                    && (currentObjective is null || !TextTools.IsContinuationPrompt(candidateObjective)))
                {
                    currentObjective = candidateObjective;
                }
                lastAssistantText = null;
                lastAssistantAt = null;
                currentTool = null;
                pendingTool = false;
            }

            if (type == "assistant" && message is not null
                && JsonTools.Array(message.Value, "content") is { } parts)
            {
                foreach (var part in parts.EnumerateArray())
                {
                    if (part.ValueKind != JsonValueKind.Object)
                    {
                        continue;
                    }
                    var partType = JsonTools.String(part, "type") ?? string.Empty;
                    if (partType == "text")
                    {
                        var text = string.Join("\n", JsonTools.CollectText(part));
                        if (!string.IsNullOrWhiteSpace(TextTools.NormalizeWhitespace(text)))
                        {
                            lastAssistantText = text;
                            lastAssistantAt = date;
                            pendingTool = false;
                        }
                    }
                    else if (partType == "tool_use")
                    {
                        var toolName = JsonTools.String(part, "name") ?? "tool";
                        currentTool = toolName;
                        pendingTool = true;
                        currentActions.Add(toolName);
                        if (JsonTools.Object(part, "input") is { } input)
                        {
                            currentFiles.AddRange(JsonTools.FilePaths(input));
                        }
                    }
                }
            }

            if (type == "error"
                || string.Equals(JsonTools.String(record, "subtype"), "error", StringComparison.OrdinalIgnoreCase))
            {
                latestErrorAt = date;
            }
        }

        var age = Max(TimeSpan.Zero, now - lastActivityAt);
        var isWaitingTool = new[] { "askuserquestion", "request_user_input", "exitplanmode" }
            .Contains(currentTool?.ToLowerInvariant());
        AgentStatus status;
        StatusConfidence confidence;
        if (latestErrorAt is not null && latestErrorAt >= (lastAssistantAt ?? DateTimeOffset.MinValue))
        {
            status = AgentStatus.Failed;
            confidence = StatusConfidence.Medium;
        }
        else if (isWaitingTool && pendingTool)
        {
            status = AgentStatus.WaitingUser;
            confidence = StatusConfidence.Medium;
        }
        else if (pendingTool)
        {
            status = age < TimeSpan.FromSeconds(240) ? AgentStatus.Working : AgentStatus.Idle;
            confidence = StatusConfidence.High;
        }
        else if (currentObjective is not null
            && (lastAssistantAt is null || (lastEventAt ?? DateTimeOffset.MinValue) > lastAssistantAt))
        {
            status = age < TimeSpan.FromSeconds(180) ? AgentStatus.Working : AgentStatus.Idle;
            confidence = StatusConfidence.Medium;
        }
        else if (lastAssistantAt is not null && lastAssistantText is not null)
        {
            var completionAge = now - lastAssistantAt.Value;
            status = completionAge < TimeSpan.FromSeconds(15)
                ? AgentStatus.Working
                : AgentStatus.Completed;
            confidence = completionAge < TimeSpan.FromSeconds(15)
                ? StatusConfidence.Medium
                : StatusConfidence.High;
        }
        else if (age < TimeSpan.FromSeconds(45))
        {
            status = AgentStatus.Starting;
            confidence = StatusConfidence.Low;
        }
        else
        {
            status = AgentStatus.Unknown;
            confidence = StatusConfidence.Low;
        }

        if (status == AgentStatus.Completed
            && currentObjective is not null
            && lastAssistantText is not null
            && lastAssistantAt is not null
            && !runs.Any(run => run.Objective == currentObjective
                && run.CompletedAt == lastAssistantAt))
        {
            runs.Add(MakeRun(
                providerSessionId,
                runs.Count,
                currentObjective,
                lastAssistantText,
                currentActions,
                currentFiles,
                lastAssistantAt.Value));
        }

        var workingDirectory = !string.IsNullOrWhiteSpace(projectPath)
            ? projectPath
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var projectName = TextTools.FileName(workingDirectory);
        if (string.IsNullOrWhiteSpace(projectName))
        {
            projectName = "未知项目";
        }

        var latestSubstantive = latestPrompt?.Text is { } promptText
            && TextTools.MeaningfulPrompt(promptText) is { } meaningful
            && !TextTools.IsContinuationPrompt(meaningful)
                ? meaningful
                : null;
        var titleSource = latestSubstantive
            ?? currentObjective
            ?? aiTitle
            ?? runs.LastOrDefault()?.Objective
            ?? projectName;

        return new AgentSession(
            $"claude:{providerSessionId}",
            AgentProvider.Claude,
            providerSessionId,
            projectName,
            workingDirectory,
            TextTools.AutomaticTaskTitle(titleSource, projectName, aiTitle),
            status,
            confidence,
            ActionFor(status, currentTool, currentFiles.LastOrDefault()),
            TextTools.Unique(currentFiles),
            startedAt <= lastActivityAt ? startedAt : lastActivityAt,
            lastActivityAt,
            status is AgentStatus.Completed or AgentStatus.Failed
                ? lastAssistantAt ?? lastActivityAt
                : null,
            runs.TakeLast(12).ToArray(),
            latestPrompt,
            filePath,
            providerIsRunning && age < TimeSpan.FromMinutes(10),
            null);
    }

    private static TaskRun MakeRun(
        string providerSessionId,
        int index,
        string objective,
        string summary,
        IReadOnlyList<string> actions,
        IReadOnlyList<string> files,
        DateTimeOffset completedAt)
    {
        return new TaskRun(
            $"{providerSessionId}:run:{index}:{completedAt.ToUnixTimeSeconds()}",
            TextTools.TitleLine(objective, 180),
            TextTools.Sentence(summary, 720),
            TextTools.Unique(actions.Select(TextTools.ReadableAction)).Take(8).ToArray(),
            TextTools.Unique(files).Take(12).ToArray(),
            completedAt,
            AgentStatus.Completed);
    }

    private static bool IsToolResult(JsonElement? content)
    {
        return content is not null
            && content.Value.ValueKind == JsonValueKind.Array
            && content.Value.EnumerateArray().Any(part =>
                part.ValueKind == JsonValueKind.Object
                && JsonTools.String(part, "type") == "tool_result");
    }

    private static DateTimeOffset EventDate(JsonElement record)
    {
        return JsonTools.TryGet(record, "timestamp", out var timestamp)
            && JsonTools.ParseDate(timestamp) is { } date
                ? date
                : DateTimeOffset.MinValue;
    }

    private static string ActionFor(AgentStatus status, string? tool, string? file)
    {
        return status switch
        {
            AgentStatus.Working => tool is null
                ? (string.IsNullOrWhiteSpace(file) ? "Agent 正在处理当前任务" : $"正在处理 {TextTools.FileName(file)}")
                : $"正在执行 {tool}",
            AgentStatus.WaitingUser => "Agent 正在等待确认或补充信息",
            AgentStatus.Completed => "本轮处理已完成，可查看总结",
            AgentStatus.Failed => "最近一轮处理出现错误",
            AgentStatus.Idle => "会话仍保留，等待下一次任务",
            AgentStatus.Starting => "已发现会话，正在读取进度",
            _ => "等待更多本地信号"
        };
    }

    private static TimeSpan Max(TimeSpan lhs, TimeSpan rhs) => lhs >= rhs ? lhs : rhs;
}
