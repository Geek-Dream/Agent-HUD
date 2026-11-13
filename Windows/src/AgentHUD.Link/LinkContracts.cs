namespace AgentHUD.Link;

public sealed record LinkedDevice(
    string Id,
    string Name,
    string TokenHash,
    DateTimeOffset PairedAt,
    DateTimeOffset? LastSeenAt,
    bool ConversationEnabled = false);

public sealed record PairingOffer(
    string Code,
    string Payload,
    DateTimeOffset ExpiresAt,
    IReadOnlyList<string> Addresses,
    int Port,
    string Fingerprint);

public sealed record PairingResult(
    string DeviceId,
    string Token,
    string InstanceId,
    string InstanceName,
    int Protocol,
    IReadOnlyList<string> Capabilities,
    string Fingerprint,
    IReadOnlyList<string> Addresses,
    int Port);

public sealed record PairCompleteRequest(
    string? SessionId,
    string? Secret,
    string? DeviceName);

public sealed record PairVerifyCodeRequest(
    string? Code,
    string? DeviceName);

public sealed record PairingSession(
    string Id,
    string Secret,
    string Code,
    DateTimeOffset ExpiresAt);

public sealed record IssuedDeviceToken(LinkedDevice Device, string Token);
