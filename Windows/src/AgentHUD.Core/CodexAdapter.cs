using System.Text.Json;

namespace AgentHUD.Core;

public static class CodexAdapter
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
        var metaRecord = sorted.FirstOrDefault(record =>
            JsonTools.String(record, "type") == "session_meta");
        var metaPayload = JsonTools.Object(metaRecord, "payload");
        var providerSessionId = JsonTools.String(metaPayload ?? default, "id")
            ?? JsonTools.String(metaPayload ?? default, "session_id")
            ?? Path.GetFileNameWithoutExtension(filePath);

        var projectPath = JsonTools.String(metaPayload ?? default, "cwd");
        var startedAt = JsonTools.Date(metaPayload, "timestamp") ?? EventDate(sorted[0]);
        var lastActivityAt = modifiedAt;
        string? currentObjective = null;
        DateTimeOffset? completedAt = null;
        DateTimeOffset? latestErrorAt = null;
        string? currentTool = null;
        var currentActions = new List<string>();
        var currentFiles = new List<string>();
        var runs = new List<TaskRun>();
        UserPromptSnapshot? latestPrompt = null;
        var activeTurn = false;
        var sawExplicitStart = false;

        foreach (var record in sorted)
        {
            var payload = JsonTools.Object(record, "payload");
            var payloadElement = payload ?? default;
            var date = EventDate(record);
            var type = JsonTools.String(record, "type") ?? string.Empty;
            var payloadType = JsonTools.String(payloadElement, "type") ?? string.Empty;

            var cwd = JsonTools.String(payloadElement, "cwd");
            if (!string.IsNullOrWhiteSpace(cwd) && Path.IsPathRooted(cwd))
            {
                projectPath = cwd;
            }

            var explicitStart = JsonTools.Date(payload, "started_at");
            if (explicitStart is not null && explicitStart < startedAt)
            {
                startedAt = explicitStart.Value;
            }
            if (date > lastActivityAt)
            {
                lastActivityAt = date;
            }

            if (type == "response_item" && payloadType == "message")
            {
                var role = JsonTools.String(payloadElement, "role");
                if (role == "user")
                {
                    var content = JsonTools.Array(payloadElement, "content");
                    var snapshot = MakePromptSnapshot(
                        string.Join("\n", JsonTools.CollectText(content)),
                        content,
                        date);
                    if (snapshot is not null)
                    {
                        latestPrompt = snapshot;
                        var candidateObjective = TextTools.MeaningfulPrompt(snapshot.Text);
                        if (candidateObjective is not null
                            && (currentObjective is null || !TextTools.IsContinuationPrompt(candidateObjective)))
                        {
                            currentObjective = candidateObjective;
                        }
                        activeTurn = true;
                    }
                }
            }

            if (type == "event_msg"
                && JsonTools.Object(payloadElement, "item") is { } eventItem
                && (payloadType.Equals("user_message", StringComparison.OrdinalIgnoreCase)
                    || (JsonTools.String(eventItem, "type") ?? string.Empty)
                        .Equals("UserMessage", StringComparison.OrdinalIgnoreCase)))
            {
                var content = JsonTools.Array(eventItem, "content");
                var snapshot = MakePromptSnapshot(
                    string.Join("\n", JsonTools.CollectText(content)),
                    content,
                    date);
                if (snapshot is not null)
                {
                    latestPrompt = snapshot;
                    var candidateObjective = TextTools.MeaningfulPrompt(snapshot.Text);
                    if (candidateObjective is not null
                        && (currentObjective is null || !TextTools.IsContinuationPrompt(candidateObjective)))
                    {
                        currentObjective = candidateObjective;
                    }
                    activeTurn = true;
                }
            }

            if (type == "response_item" && payloadType == "function_call")
            {
                var tool = JsonTools.String(payloadElement, "name") ?? "tool";
                currentTool = tool;
                activeTurn = true;
                sawExplicitStart = true;
                currentActions.Add(tool);

                var arguments = ParseArguments(JsonTools.String(payloadElement, "arguments"));
                currentFiles.AddRange(JsonTools.FilePaths(arguments));
                if (arguments is not null)
                {
                    var command = JsonTools.String(arguments.Value, "cmd")
                        ?? JsonTools.String(arguments.Value, "command");
                    if (!string.IsNullOrWhiteSpace(command))
                    {
                        currentActions.Add(command);
                    }
                }
            }

            if (type == "event_msg" && payloadType == "task_started")
            {
                activeTurn = true;
                sawExplicitStart = true;
                currentTool = null;
            }

            if (type == "event_msg" && payloadType == "item_completed"
                && JsonTools.Object(payloadElement, "item") is { } completedItem)
            {
                var itemType = JsonTools.String(completedItem, "type");
                if (itemType is "command_execution" or "command")
                {
                    var command = JsonTools.String(completedItem, "command");
                    if (!string.IsNullOrWhiteSpace(command))
                    {
                        currentActions.Add(command);
                    }
                }
                var tool = JsonTools.String(completedItem, "name");
                if (!string.IsNullOrWhiteSpace(tool))
                {
                    currentTool = tool;
                }
                currentFiles.AddRange(JsonTools.FilePaths(completedItem));
            }

            if (type == "event_msg" && payloadType == "task_complete")
            {
                var summary = JsonTools.String(payloadElement, "last_agent_message")
                    ?? "本轮任务完成，没有可提取的完成说明。";
                var completionDate = JsonTools.Date(payload, "completed_at") ?? date;
                runs.Add(MakeRun(
                    providerSessionId,
                    runs.Count,
                    currentObjective ?? "未记录任务目标",
                    summary,
                    currentActions,
                    currentFiles,
                    completionDate));
                completedAt = completionDate;
                activeTurn = false;
                currentTool = null;
                currentActions.Clear();
                currentFiles.Clear();
            }

            if (payloadType.Contains("error", StringComparison.OrdinalIgnoreCase)
                || (type.Contains("error", StringComparison.OrdinalIgnoreCase)
                    && payloadType != "item_completed"))
            {
                latestErrorAt = date;
                activeTurn = false;
            }
        }

        var age = Max(TimeSpan.Zero, now - lastActivityAt);
        AgentStatus status;
        StatusConfidence confidence;
        if (latestErrorAt is not null && latestErrorAt >= (completedAt ?? DateTimeOffset.MinValue))
        {
            status = AgentStatus.Failed;
            confidence = StatusConfidence.High;
        }
        else if (activeTurn)
        {
            status = age < TimeSpan.FromSeconds(180) ? AgentStatus.Working : AgentStatus.Idle;
            confidence = sawExplicitStart || currentTool is not null
                ? StatusConfidence.High
                : StatusConfidence.Medium;
        }
        else if (completedAt is not null)
        {
            status = AgentStatus.Completed;
            confidence = StatusConfidence.High;
        }
        else if (age < TimeSpan.FromSeconds(45))
        {
            status = AgentStatus.Starting;
            confidence = StatusConfidence.Medium;
        }
        else
        {
            status = AgentStatus.Unknown;
            confidence = StatusConfidence.Low;
        }

        var fallbackTitle = Path.GetFileNameWithoutExtension(filePath);
        var latestSubstantive = latestPrompt?.Text is { } promptText
            && TextTools.MeaningfulPrompt(promptText) is { } meaningful
            && !TextTools.IsContinuationPrompt(meaningful)
                ? meaningful
                : null;
        var titleSource = latestSubstantive
            ?? currentObjective
            ?? runs.LastOrDefault()?.Objective
            ?? JsonTools.String(metaPayload ?? default, "thread_source")
            ?? fallbackTitle;

        var workingDirectory = !string.IsNullOrWhiteSpace(projectPath)
            ? projectPath
            : Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var projectName = TextTools.FileName(workingDirectory);
        if (string.IsNullOrWhiteSpace(projectName))
        {
            projectName = "未知项目";
        }

        return new AgentSession(
            $"codex:{providerSessionId}",
            AgentProvider.Codex,
            providerSessionId,
            projectName,
            workingDirectory,
            TextTools.AutomaticTaskTitle(titleSource, projectName),
            status,
            confidence,
            CurrentAction(status, currentTool, currentFiles.LastOrDefault()),
            TextTools.Unique(currentFiles),
            startedAt <= lastActivityAt ? startedAt : lastActivityAt,
            lastActivityAt,
            status is AgentStatus.Completed or AgentStatus.Failed
                ? completedAt ?? lastActivityAt
                : null,
            runs.TakeLast(12).ToArray(),
            latestPrompt,
            filePath,
            providerIsRunning && age < TimeSpan.FromMinutes(10),
            null);
    }

    private static UserPromptSnapshot? MakePromptSnapshot(
        string text,
        JsonElement? content,
        DateTimeOffset sentAt)
    {
        var promptText = TextTools.UserPromptText(text);
        var images = SessionAttachmentParser.CodexImages(content);
        if (string.IsNullOrWhiteSpace(promptText) && images.Count == 0)
        {
            return null;
        }
        return new UserPromptSnapshot(
            promptText,
            sentAt == DateTimeOffset.MinValue ? null : sentAt,
            images);
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
            TextTools.Sentence(summary, 640),
            TextTools.Unique(actions.Select(TextTools.ReadableAction)).Take(8).ToArray(),
            TextTools.Unique(files).Take(12).ToArray(),
            completedAt,
            AgentStatus.Completed);
    }

    private static DateTimeOffset EventDate(JsonElement record)
    {
        if (JsonTools.TryGet(record, "timestamp", out var timestamp)
            && JsonTools.ParseDate(timestamp) is { } value)
        {
            return value;
        }
        if (JsonTools.Object(record, "payload") is { } payload)
        {
            foreach (var property in new[] { "started_at", "completed_at", "started_at_ms", "completed_at_ms" })
            {
                if (JsonTools.TryGet(payload, property, out var child)
                    && JsonTools.ParseDate(child) is { } childValue)
                {
                    return childValue;
                }
            }
        }
        return DateTimeOffset.MinValue;
    }

    private static JsonElement? ParseArguments(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }
        try
        {
            using var document = JsonDocument.Parse(value);
            return document.RootElement.Clone();
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string CurrentAction(
        AgentStatus status,
        string? tool,
        string? file)
    {
        return status switch
        {
            AgentStatus.Working => DescribeAction(tool, file),
            AgentStatus.Idle => "会话仍保留，等待下一次任务",
            AgentStatus.Completed => "最近一轮处理已完成",
            AgentStatus.Failed => "最近一轮处理出现错误",
            AgentStatus.Starting => "已发现会话，正在读取进度",
            _ => "正在等待更多本地信号"
        };
    }

    private static string DescribeAction(string? toolName, string? detail)
    {
        var tool = TextTools.NormalizeWhitespace(toolName);
        var name = TextTools.FileName(detail);
        if (tool.Length == 0)
        {
            return name.Length == 0 ? "Agent 正在处理当前任务" : $"正在处理 {name}";
        }
        return name.Length == 0 ? $"正在执行 {tool}" : $"正在用 {tool} 处理 {name}";
    }

    private static TimeSpan Max(TimeSpan lhs, TimeSpan rhs) => lhs >= rhs ? lhs : rhs;
}
