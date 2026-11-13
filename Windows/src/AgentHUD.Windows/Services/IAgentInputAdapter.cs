using AgentHUD.Core;
using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

public interface IAgentInputAdapter
{
    AgentProvider Provider { get; }
    InputCapability CanAcceptInput(AgentSession session);
    Task<DeliveryResult> DeliverAsync(string text, AgentSession session);
}

public sealed record InputCapability(bool Enabled, InputState State, string? Reason);

public sealed record DeliveryResult(bool Success, DeliveryStatus Status, DeliveryError? Error);
