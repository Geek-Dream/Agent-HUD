namespace AgentHUD.Link;

public interface IMonitoringSnapshotSource
{
    MonitoringSnapshot GetMonitoringSnapshot();
}

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
    string? Summary);
