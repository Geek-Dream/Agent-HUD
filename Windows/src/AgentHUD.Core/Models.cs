namespace AgentHUD.Core;

public enum AgentProvider
{
    Codex,
    Claude,
    Pi
}

public enum AgentStatus
{
    Starting,
    Working,
    WaitingUser,
    Idle,
    Completed,
    Failed,
    Unknown
}

public enum StatusConfidence
{
    High,
    Medium,
    Low
}

public enum StatusFilter
{
    All,
    Working,
    Waiting,
    Completed,
    Failed
}

public enum ProviderFilter
{
    All,
    Codex,
    Claude,
    Pi
}

public enum TitleSource
{
    Automatic,
    AI,
    User
}

public sealed record TaskRun(
    string Id,
    string Objective,
    string Summary,
    IReadOnlyList<string> Actions,
    IReadOnlyList<string> FilesChanged,
    DateTimeOffset CompletedAt,
    AgentStatus Status);

public sealed record SessionImageAttachment(
    string Id,
    string? LocalPath,
    string? DataUrl,
    string? Label)
{
    public static string DisplayLabel(int index) => $"[图片{index + 1}]";
}

public sealed record UserPromptSnapshot(
    string Text,
    DateTimeOffset? SentAt,
    IReadOnlyList<SessionImageAttachment> Images);

public sealed record GitContext(
    string RepoRoot,
    string Branch,
    int ChangedFiles,
    int Insertions,
    int Deletions,
    bool IsDirty);

public sealed record AgentSession(
    string Id,
    AgentProvider Provider,
    string ProviderSessionId,
    string ProjectName,
    string ProjectPath,
    string Title,
    AgentStatus Status,
    StatusConfidence Confidence,
    string CurrentAction,
    IReadOnlyList<string> CurrentFiles,
    DateTimeOffset StartedAt,
    DateTimeOffset LastActivityAt,
    DateTimeOffset? CompletedAt,
    IReadOnlyList<TaskRun> Runs,
    UserPromptSnapshot? LatestUserPrompt,
    string SourcePath,
    bool IsLive,
    GitContext? Git)
{
    public TimeSpan Duration => (CompletedAt ?? LastActivityAt) - StartedAt;
}

public sealed record DashboardSnapshot(
    IReadOnlyList<AgentSession> Sessions,
    DateTimeOffset ScannedAt)
{
    public static DashboardSnapshot Empty { get; } =
        new(Array.Empty<AgentSession>(), DateTimeOffset.Now);
}

public sealed record ImportantCompletionNotice(
    string SessionId,
    AgentProvider Provider,
    string Title,
    string ProjectName);

public static class ModelLabels
{
    public static string ShortName(this AgentProvider provider) => provider switch
    {
        AgentProvider.Codex => "CODEX",
        AgentProvider.Claude => "CLAUDE",
        AgentProvider.Pi => "PI",
        _ => "AGENT"
    };

    public static string DisplayName(this AgentProvider provider) => provider switch
    {
        AgentProvider.Codex => "Codex",
        AgentProvider.Claude => "Claude Code",
        AgentProvider.Pi => "Pi",
        _ => "Agent"
    };

    public static string ShortLabel(this AgentStatus status) => status switch
    {
        AgentStatus.Starting => "启动",
        AgentStatus.Working => "工作",
        AgentStatus.WaitingUser => "等待",
        AgentStatus.Idle => "空闲",
        AgentStatus.Completed => "完成",
        AgentStatus.Failed => "错误",
        _ => "未知"
    };

    public static string Label(this AgentStatus status) => status switch
    {
        AgentStatus.Starting => "启动中",
        AgentStatus.Working => "工作中",
        AgentStatus.WaitingUser => "等待确认",
        AgentStatus.Idle => "空闲",
        AgentStatus.Completed => "已完成",
        AgentStatus.Failed => "出错",
        _ => "未知"
    };

    public static string Label(this StatusConfidence confidence) => confidence switch
    {
        StatusConfidence.High => "高可信",
        StatusConfidence.Medium => "推断",
        _ => "低可信"
    };

    public static string Label(this StatusFilter filter) => filter switch
    {
        StatusFilter.All => "全部",
        StatusFilter.Working => "工作",
        StatusFilter.Waiting => "等待",
        StatusFilter.Completed => "完成",
        StatusFilter.Failed => "错误",
        _ => "全部"
    };

    public static string Label(this ProviderFilter filter) => filter switch
    {
        ProviderFilter.All => "全部",
        ProviderFilter.Codex => "Codex",
        ProviderFilter.Claude => "Claude",
        ProviderFilter.Pi => "Pi",
        _ => "全部"
    };

    public static string Label(this TitleSource source) => source switch
    {
        TitleSource.User => "我的备注",
        TitleSource.AI => "AI 概括",
        _ => "本地概括"
    };

    public static bool IsRunning(this AgentStatus status) =>
        status is AgentStatus.Starting or AgentStatus.Working;

    public static bool IsActive(this AgentStatus status) =>
        status is AgentStatus.Starting or AgentStatus.Working or AgentStatus.WaitingUser;

    public static int SortRank(this AgentStatus status) => status switch
    {
        AgentStatus.WaitingUser => 0,
        AgentStatus.Failed => 1,
        AgentStatus.Working => 2,
        AgentStatus.Starting => 3,
        AgentStatus.Completed => 4,
        AgentStatus.Idle => 5,
        _ => 6
    };

    public static bool Matches(this StatusFilter filter, AgentStatus status) => filter switch
    {
        StatusFilter.All => true,
        StatusFilter.Working => status is AgentStatus.Working or AgentStatus.Starting,
        StatusFilter.Waiting => status == AgentStatus.WaitingUser,
        StatusFilter.Completed => status == AgentStatus.Completed,
        StatusFilter.Failed => status == AgentStatus.Failed,
        _ => true
    };

    public static bool Matches(this ProviderFilter filter, AgentProvider provider) => filter switch
    {
        ProviderFilter.All => true,
        ProviderFilter.Codex => provider == AgentProvider.Codex,
        ProviderFilter.Claude => provider == AgentProvider.Claude,
        ProviderFilter.Pi => provider == AgentProvider.Pi,
        _ => true
    };
}

public static class SessionOrdering
{
    public static IReadOnlyList<AgentSession> Sort(
        IEnumerable<AgentSession> sessions,
        ISet<string> importantSessionIds,
        bool runningFirst = false)
    {
        return sessions
            .OrderByDescending(session => importantSessionIds.Contains(session.Id))
            .ThenBy(session => runningFirst && !session.Status.IsRunning())
            .ThenBy(session => session.Status.SortRank())
            .ThenByDescending(session => session.LastActivityAt)
            .ThenBy(session => session.Id, StringComparer.Ordinal)
            .ToArray();
    }
}

public static class SessionTransitionDetector
{
    public static IReadOnlySet<string> RunningCompletionIds(
        IReadOnlyList<AgentSession> previousSessions,
        IReadOnlyList<AgentSession> currentSessions)
    {
        var current = currentSessions.ToDictionary(session => session.Id, session => session.Status);
        return previousSessions
            .Where(session => session.Status.IsRunning()
                && current.TryGetValue(session.Id, out var status)
                && status == AgentStatus.Completed)
            .Select(session => session.Id)
            .ToHashSet(StringComparer.Ordinal);
    }
}

public sealed class SessionTitleResolver
{
    public ResolvedTitle Resolve(
        string sessionId,
        string localTitle,
        IReadOnlyDictionary<string, string> manualTitles,
        IReadOnlyDictionary<string, string> aiTitles)
    {
        if (manualTitles.TryGetValue(sessionId, out var manual)
            && !string.IsNullOrWhiteSpace(manual))
        {
            return new ResolvedTitle(manual.Trim(), TitleSource.User);
        }

        if (aiTitles.TryGetValue(sessionId, out var ai)
            && !string.IsNullOrWhiteSpace(ai))
        {
            return new ResolvedTitle(ai.Trim(), TitleSource.AI);
        }

        return new ResolvedTitle(localTitle, TitleSource.Automatic);
    }
}

public sealed record ResolvedTitle(string Value, TitleSource Source);
