using System.Text.Json;

namespace AgentHUD.Core;

public static class ClaudeAdapter
{
    public static AgentSession? Parse(
        IReadOnlyList<JsonElement> records,
        string filePath,
        DateTimeOffset modifiedAt,
        bool providerIsRunning,
        DateTimeOffset now,
        IReadOnlyList<JsonElement>? subagentRecords = null)
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

        // Claude Code writes bookkeeping rows (last-prompt / mode / ai-title …)
        // without a timestamp. Sorting puts them first, so taking the head's
        // date yields DateTimeOffset.MinValue and every session ends up with a
        // year-0001 start time and a 700k-hour duration. Use the first row that
        // actually carries a timestamp, then fall back to the file mtime.
        var firstDated = sorted
            .Select(EventDate)
            .FirstOrDefault(date => date > DateTimeOffset.MinValue);
        var startedAt = firstDated > DateTimeOffset.MinValue ? firstDated : modifiedAt;
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
        var latestUserPromptAt = DateTimeOffset.MinValue;
        DateTimeOffset? turnCompletedAt = null;

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
                // A real user prompt is stored either as a bare string or as an
                // array of parts. Only the array form was handled, so every
                // string prompt was silently dropped — the session then had no
                // prompt at all and fell back to a generic "处理XX项目" title.
                var rawContent = default(JsonElement);
                var hasContent = message is not null
                    && JsonTools.TryGet(message.Value, "content", out rawContent);
                var content = hasContent && rawContent.ValueKind == JsonValueKind.Array
                    ? rawContent
                    : (JsonElement?)null;
                if (IsToolResult(content))
                {
                    pendingTool = false;
                    continue;
                }
                if (JsonTools.Bool(record, "isMeta") == true || !hasContent)
                {
                    continue;
                }

                var latestPromptText = TextTools.UserPromptText(rawContent.ValueKind == JsonValueKind.String
                    ? rawContent.GetString()
                    : string.Join("\n", JsonTools.CollectText(content)));
                var images = SessionAttachmentParser.ClaudeImages(content);
                if (string.IsNullOrWhiteSpace(latestPromptText) && images.Count == 0)
                {
                    continue;
                }

                latestPrompt = new UserPromptSnapshot(
                    latestPromptText,
                    date == DateTimeOffset.MinValue ? null : date,
                    images);
                latestUserPromptAt = date;
                turnCompletedAt = null;

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

            // Claude Code closes every turn with a system/turn_duration row.
            // That is the only unambiguous "finished" marker in the log; relying
            // on "assistant wrote text" alone made the session look busy until
            // the 180 s idle timer expired.
            if (type == "system"
                && string.Equals(JsonTools.String(record, "subtype"), "turn_duration", StringComparison.OrdinalIgnoreCase))
            {
                turnCompletedAt = date;
            }
        }

        var age = Max(TimeSpan.Zero, now - lastActivityAt);
        var isWaitingTool = new[] { "askuserquestion", "request_user_input", "exitplanmode" }
            .Contains(currentTool?.ToLowerInvariant());

        // A delegated child (Task / subagent) keeps the parent busy. Claude Code
        // records the child in a sibling transcript that shares the session id,
        // so without this the parent flips to 完成 mid-task while children run.
        var subagentLastAt = subagentRecords is null ? null : LastSubagentActivity(subagentRecords);
        var subagentRunning = subagentLastAt is { } subagentAt && now - subagentAt < TimeSpan.FromSeconds(90);

        AgentStatus status;
        StatusConfidence confidence;
        if (latestErrorAt is not null
            && latestErrorAt >= (lastAssistantAt ?? DateTimeOffset.MinValue)
            && latestErrorAt >= latestUserPromptAt)
        {
            status = AgentStatus.Failed;
            confidence = StatusConfidence.Medium;
        }
        else if (isWaitingTool && pendingTool)
        {
            status = AgentStatus.WaitingUser;
            confidence = StatusConfidence.Medium;
        }
        else if (subagentRunning)
        {
            status = AgentStatus.Working;
            confidence = StatusConfidence.High;
            if (subagentLastAt > lastActivityAt)
            {
                lastActivityAt = subagentLastAt.Value;
                age = Max(TimeSpan.Zero, now - lastActivityAt);
            }
        }
        else if (pendingTool)
        {
            status = age < TimeSpan.FromSeconds(240) ? AgentStatus.Working : AgentStatus.Idle;
            confidence = StatusConfidence.High;
        }
        else if (latestUserPromptAt > (lastAssistantAt ?? DateTimeOffset.MinValue))
        {
            // The user spoke after the last assistant answer, so a turn is in
            // flight even though nothing has landed in the log yet. Checked
            // before the completion marker because a stale `turn_duration` from
            // the previous turn must not mark the new prompt as finished.
            status = age < TimeSpan.FromSeconds(180) ? AgentStatus.Working : AgentStatus.Idle;
            confidence = StatusConfidence.Medium;
        }
        else if (turnCompletedAt is not null
            && turnCompletedAt > (lastAssistantAt ?? DateTimeOffset.MinValue))
        {
            // Turn closed and no tool is outstanding: the session is done.
            status = AgentStatus.Completed;
            confidence = StatusConfidence.High;
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

    private static DateTimeOffset? LastSubagentActivity(IReadOnlyList<JsonElement> records)
    {
        var latest = DateTimeOffset.MinValue;
        foreach (var record in records)
        {
            var date = EventDate(record);
            if (date > latest)
            {
                latest = date;
            }
        }
        return latest > DateTimeOffset.MinValue ? latest : null;
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
