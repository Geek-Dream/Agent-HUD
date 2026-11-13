namespace AgentHUD.Link;

public interface IMonitoringSnapshotSource
{
    MonitoringSnapshot GetMonitoringSnapshot();

    bool SetSessionTitle(string sessionId, string? title) => false;

    bool SetSessionImportant(string sessionId, bool important) => false;

    SessionImagePayload? GetPromptImage(string sessionId, int index) => null;

    string SendMessage(string sessionId, string clientMessageId, string text) => string.Empty;

    (DeliveryStatus Status, DeliveryError? Error)? GetDeliveryStatus(string deliveryId) => null;
}

public sealed record SessionImagePayload(byte[] Data, string ContentType);

public sealed record MonitoringPromptImage(int Index, string Label);

public sealed record MonitoringPromptSnapshot(
    string Text,
    DateTimeOffset? SentAt,
    IReadOnlyList<MonitoringPromptImage> Images);

public sealed record MonitoringTaskRun(
    string Id,
    string Objective,
    string Summary,
    IReadOnlyList<string> Actions,
    IReadOnlyList<string> FilesChanged,
    DateTimeOffset CompletedAt,
    string Status);

public sealed record MonitoringSnapshot(
    long Revision,
    DateTimeOffset? ScannedAt,
    bool PrivacyMode,
    IReadOnlyList<MonitoringSessionSnapshot> Sessions);

public sealed record ConversationCapability(
    bool Enabled,
    string State,
    string? Reason);

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
    MonitoringPromptSnapshot? LatestPrompt = null,
    IReadOnlyList<MonitoringTaskRun> Runs = null!,
    ConversationCapability? Conversation = null);

public sealed record MessageRequest(string? ClientMessageId, string? Text);

public sealed record MessageResponse(string DeliveryId, string ClientMessageId, string Status);

public sealed record DeliveryResponse(string DeliveryId, string ClientMessageId, string Status, string? Error);

public enum DeliveryStatus
{
    Accepted,
    Delivered,
    Observed,
    Failed
}

public enum DeliveryError
{
    SessionOffline,
    ProviderUnsupported,
    InputUnavailable,
    AgentBusy,
    InvalidMessage,
    DeliveryFailed
}

public enum InputState
{
    Ready,
    Busy,
    WaitingUser,
    Offline,
    Unsupported,
    Unavailable
}

public sealed record InputCapability(bool Enabled, InputState State, string? Reason);
