using System.Text.Json;

namespace AgentHUD.Core;

public sealed record OpenCodeEvent(
    string Id,
    DateTimeOffset Date,
    JsonElement Data,
    string? MessageID = null);

public sealed record OpenCodeSessionRecord(
    string Id,
    string Directory,
    string Title,
    DateTimeOffset CreatedAt,
    DateTimeOffset UpdatedAt,
    IReadOnlyList<OpenCodeEvent> Messages,
    IReadOnlyList<OpenCodeEvent> Parts);

public static class OpenCodeAdapter
{
    public static AgentSession Parse(
        OpenCodeSessionRecord record,
        string filePath,
        bool providerIsRunning,
        DateTimeOffset now)
    {
        var partsByMessage = record.Parts
            .GroupBy(part => part.MessageID ?? JsonTools.String(part.Data, "messageID") ?? string.Empty)
            .ToDictionary(group => group.Key, group => group.ToArray());
        var messages = record.Messages
            .OrderBy(message => message.Date)
            .ThenBy(message => message.Id, StringComparer.Ordinal)
            .ToArray();

        string? currentObjective = null;
        var currentActions = new List<string>();
        var currentFiles = new List<string>();
        string? currentTool = null;
        var pendingTool = false;
        string? lastAssistantText = null;
        DateTimeOffset? lastAssistantAt = null;
        DateTimeOffset? latestUserAt = null;
        DateTimeOffset? latestErrorAt = null;
        UserPromptSnapshot? latestPrompt = null;
        var runs = new List<TaskRun>();
        var lastActivityAt = record.UpdatedAt;

        foreach (var message in messages)
        {
            lastActivityAt = Max(lastActivityAt, message.Date);
            var role = JsonTools.String(message.Data, "role") ?? string.Empty;
            var messageParts = partsByMessage.TryGetValue(message.Id, out var values)
                ? values.OrderBy(part => part.Date).ThenBy(part => part.Id, StringComparer.Ordinal).ToArray()
                : Array.Empty<OpenCodeEvent>();

            if (role == "user")
            {
                var text = string.Join("\n", messageParts
                    .Where(part => JsonTools.String(part.Data, "type") == "text")
                    .Select(part => JsonTools.String(part.Data, "text"))
                    .Where(value => !string.IsNullOrWhiteSpace(value)));
                var promptText = TextTools.UserPromptText(text);
                if (string.IsNullOrWhiteSpace(promptText))
                {
                    continue;
                }

                latestPrompt = new UserPromptSnapshot(
                    promptText,
                    message.Date,
                    Array.Empty<SessionImageAttachment>());
                latestUserAt = message.Date;
                latestErrorAt = null;
                pendingTool = false;
                currentTool = null;

                if (currentObjective is not null
                    && lastAssistantText is not null
                    && lastAssistantAt is { } completedAt
                    && !runs.Any(run =>
                        run.Objective == currentObjective && run.CompletedAt == completedAt))
                {
                    runs.Add(MakeRun(
                        record.Id,
                        runs.Count,
                        currentObjective,
                        lastAssistantText,
                        currentActions,
                        currentFiles,
                        completedAt));
                    currentActions.Clear();
                    currentFiles.Clear();
                }

                if (TextTools.MeaningfulPrompt(promptText) is { } prompt
                    && (currentObjective is null || !TextTools.IsContinuationPrompt(prompt)))
                {
                    currentObjective = prompt;
                }
                lastAssistantText = null;
                lastAssistantAt = null;
                continue;
            }

            if (role != "assistant")
            {
                continue;
            }

            foreach (var part in messageParts)
            {
                lastActivityAt = Max(lastActivityAt, part.Date);
                var type = JsonTools.String(part.Data, "type") ?? string.Empty;
                if (type == "text"
                    && JsonTools.String(part.Data, "text") is { } text
                    && !string.IsNullOrWhiteSpace(TextTools.NormalizeWhitespace(text)))
                {
                    lastAssistantText = text;
                    lastAssistantAt = NestedDate(part.Data, "end")
                        ?? NestedDate(message.Data, "completed")
                        ?? part.Date;
                }

                if (type == "patch")
                {
                    currentFiles.AddRange(StringArray(part.Data, "files"));
                }
                if (type != "tool")
                {
                    continue;
                }

                var tool = JsonTools.String(part.Data, "tool") ?? "tool";
                var state = JsonTools.Object(part.Data, "state");
                var input = state is null ? null : JsonTools.Object(state.Value, "input");
                var toolStatus = state is null
                    ? string.Empty
                    : JsonTools.String(state.Value, "status")?.ToLowerInvariant() ?? string.Empty;
                currentTool = tool;
                currentActions.Add(tool);
                if (input is not null && JsonTools.String(input.Value, "command") is { } command)
                {
                    currentActions.Add(command);
                }
                currentFiles.AddRange(JsonTools.FilePaths(input));
                if (input is not null)
                {
                    foreach (var key in new[] { "filePath", "path", "file", "file_path" })
                    {
                        if (JsonTools.String(input.Value, key) is { } path)
                        {
                            currentFiles.Add(path);
                        }
                    }
                }
                currentFiles.AddRange(JsonTools.FilePaths(JsonTools.Array(part.Data, "files")));

                switch (toolStatus)
                {
                    case "running":
                    case "pending":
                    case "waiting":
                    case "waiting_user":
                    case "waitinguser":
                        pendingTool = true;
                        break;
                    case "error":
                    case "failed":
                    case "failure":
                        pendingTool = false;
                        latestErrorAt = part.Date;
                        break;
                    default:
                        pendingTool = false;
                        break;
                }
            }

            if (lastAssistantAt is null && NestedDate(message.Data, "completed") is { } completed)
            {
                lastAssistantAt = completed;
            }
        }

        var age = now - lastActivityAt;
        if (age < TimeSpan.Zero)
        {
            age = TimeSpan.Zero;
        }
        var waitingTools = new[] { "question", "askuserquestion", "request_user_input", "exitplanmode" };
        AgentStatus status;
        StatusConfidence confidence;

        if (latestErrorAt is not null)
        {
            status = AgentStatus.Failed;
            confidence = StatusConfidence.High;
        }
        else if (pendingTool && waitingTools.Contains(currentTool?.ToLowerInvariant() ?? string.Empty))
        {
            status = AgentStatus.WaitingUser;
            confidence = StatusConfidence.High;
        }
        else if (pendingTool)
        {
            status = age < TimeSpan.FromSeconds(240) ? AgentStatus.Working : AgentStatus.Idle;
            confidence = StatusConfidence.High;
        }
        else if (currentObjective is not null
            && (lastAssistantAt is null || latestUserAt > lastAssistantAt))
        {
            status = age < TimeSpan.FromSeconds(180) ? AgentStatus.Working : AgentStatus.Idle;
            confidence = StatusConfidence.Medium;
        }
        else if (lastAssistantAt is { } assistantAt && lastAssistantText is not null)
        {
            var completionAge = now - assistantAt;
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
            && lastAssistantAt is { } finalCompletedAt
            && !runs.Any(run =>
                run.Objective == currentObjective && run.CompletedAt == finalCompletedAt))
        {
            runs.Add(MakeRun(
                record.Id,
                runs.Count,
                currentObjective,
                lastAssistantText,
                currentActions,
                currentFiles,
                finalCompletedAt));
        }

        var projectName = TextTools.FileName(record.Directory);
        if (string.IsNullOrWhiteSpace(projectName))
        {
            projectName = "未知项目";
        }
        var latestSubstantive = latestPrompt?.Text is { } promptText
            && TextTools.MeaningfulPrompt(promptText) is { } meaningful
            && !TextTools.IsContinuationPrompt(meaningful)
                ? meaningful
                : null;
        var titleSource = latestSubstantive ?? currentObjective ?? record.Title;

        return new AgentSession(
            $"opencode:{record.Id}",
            AgentProvider.OpenCode,
            record.Id,
            projectName,
            record.Directory,
            TextTools.AutomaticTaskTitle(titleSource, projectName, record.Title),
            status,
            confidence,
            ActionFor(status, currentTool, currentFiles.LastOrDefault()),
            TextTools.Unique(currentFiles),
            record.CreatedAt <= lastActivityAt ? record.CreatedAt : lastActivityAt,
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

    private static DateTimeOffset? NestedDate(JsonElement value, string key)
    {
        return JsonTools.Object(value, "time") is { } time
            ? JsonTools.Date(time, key)
            : null;
    }

    private static IEnumerable<string> StringArray(JsonElement value, string property)
    {
        return JsonTools.Array(value, property) is { } values
            ? values.EnumerateArray()
                .Where(item => item.ValueKind == JsonValueKind.String)
                .Select(item => item.GetString()!)
            : Array.Empty<string>();
    }

    private static TaskRun MakeRun(
        string sessionID,
        int index,
        string objective,
        string summary,
        IReadOnlyList<string> actions,
        IReadOnlyList<string> files,
        DateTimeOffset completedAt)
    {
        return new TaskRun(
            $"{sessionID}:run:{index}:{completedAt.ToUnixTimeSeconds()}",
            TextTools.TitleLine(objective, 180),
            TextTools.Sentence(summary, 720),
            TextTools.Unique(actions.Select(TextTools.ReadableAction)).Take(8).ToArray(),
            TextTools.Unique(files).Take(12).ToArray(),
            completedAt,
            AgentStatus.Completed);
    }

    private static string ActionFor(AgentStatus status, string? tool, string? file) => status switch
    {
        AgentStatus.Working => tool is null
            ? (string.IsNullOrWhiteSpace(file) ? "OpenCode 正在处理当前任务" : $"正在处理 {TextTools.FileName(file)}")
            : $"正在执行 {tool}",
        AgentStatus.WaitingUser => "OpenCode 正在等待确认或补充信息",
        AgentStatus.Completed => "本轮处理已完成，可查看总结",
        AgentStatus.Failed => "最近一轮处理出现错误",
        AgentStatus.Idle => "会话仍保留，等待下一次任务",
        AgentStatus.Starting => "已发现 OpenCode 会话，正在读取进度",
        _ => "等待更多本地信号"
    };

    private static DateTimeOffset Max(DateTimeOffset lhs, DateTimeOffset rhs) =>
        lhs >= rhs ? lhs : rhs;
}
