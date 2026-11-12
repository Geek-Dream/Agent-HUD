namespace AgentHUD.Link;

public interface IMonitoringSnapshotSource
{
    MonitoringSnapshot GetMonitoringSnapshot();

    bool SetSessionTitle(string sessionId, string? title) => false;

    bool SetSessionImportant(string sessionId, bool important) => false;

    SessionImagePayload? GetPromptImage(string sessionId, int index) => null;
}

public sealed record SessionImagePayload(byte[] Data, string ContentType);

public sealed record MonitoringPromptImage(int Index, string Label);

public sealed record MonitoringPromptSnapshot(
    string Text,
    DateTimeOffset? SentAt,
    IReadOnlyList<MonitoringPromptImage> Images);

public sealed record MonitoringSnapshot(
    long Revision,
    DateTimeOffset? ScannedAt,
    bool PrivacyMode,
    IReadOnlyList<MonitoringSessionSnapshot> Sessions);

public sealed record MonitoringSessionSnapshot(
    string Id,
    string Provider,
    string Status,
    string Confidence,
    string Title,
    string ProjectName,
    string CurrentAction,
    IReadOnlyList<string> CurrentFiles,
    DateTimeOffset StartedAt,
    DateTimeOffset LastActivityAt,
    DateTimeOffset? CompletedAt,
    bool IsLive,
    string? GitBranch,
    int? GitChangedFiles,
    int? GitInsertions,
    int? GitDeletions,
    string? Summary,
    bool IsImportant = false,
    string TitleSource = "Automatic",
    bool HasCustomTitle = false,
    MonitoringPromptSnapshot? LatestPrompt = null);
