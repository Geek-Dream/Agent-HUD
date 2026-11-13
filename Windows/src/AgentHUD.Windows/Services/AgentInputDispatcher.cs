using System.Collections.Concurrent;
using AgentHUD.Core;
using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

public sealed class AgentInputDispatcher
{
    private readonly IReadOnlyDictionary<AgentProvider, IReadOnlyList<IAgentInputAdapter>> _adapters;
    private readonly DeliveryStore _deliveryStore = new();
    private readonly ConcurrentDictionary<string, bool> _inFlight = new();
    private const int MaxTextLength = 4000;

    public AgentInputDispatcher()
    {
        _adapters = new Dictionary<AgentProvider, IReadOnlyList<IAgentInputAdapter>>
        {
            [AgentProvider.Codex] = [new CodexInputAdapter()]
        };
    }

    public InputCapability CapabilityFor(AgentSession session)
    {
        if (!session.IsLive)
        {
            return new InputCapability(false, InputState.Offline, "会话或进程已经离线。");
        }

        if (!_adapters.TryGetValue(session.Provider, out var adapters) || adapters.Count == 0)
        {
            return new InputCapability(false, InputState.Unsupported, "当前 Provider 或版本不支持输入。");
        }

        foreach (var adapter in adapters)
        {
            var capability = adapter.CanAcceptInput(session);
            if (capability.State == InputState.Ready)
            {
                return capability;
            }
        }

        foreach (var adapter in adapters)
        {
            var capability = adapter.CanAcceptInput(session);
            if (capability.State == InputState.WaitingUser)
            {
                return capability;
            }
        }

        return adapters[0].CanAcceptInput(session);
    }

    public string Dispatch(string clientMessageId, string text, AgentSession session, string publicSessionId)
    {
        if (_deliveryStore.Find(clientMessageId) is { } existing)
        {
            return existing.DeliveryId;
        }

        var deliveryId = _deliveryStore.Create(clientMessageId, publicSessionId, text);

        var trimmed = text.Trim();
        if (string.IsNullOrEmpty(clientMessageId) || string.IsNullOrWhiteSpace(trimmed) || trimmed.Length > MaxTextLength)
        {
            _deliveryStore.Update(deliveryId, DeliveryStatus.Failed, DeliveryError.InvalidMessage);
            return deliveryId;
        }

        var capability = CapabilityFor(session);
        if (!capability.Enabled)
        {
            var error = capability.State switch
            {
                InputState.Offline => DeliveryError.SessionOffline,
                InputState.Unsupported => DeliveryError.ProviderUnsupported,
                _ => DeliveryError.InputUnavailable
            };
            _deliveryStore.Update(deliveryId, DeliveryStatus.Failed, error);
            return deliveryId;
        }

        if (!_inFlight.TryAdd(session.Id, true))
        {
            _deliveryStore.Update(deliveryId, DeliveryStatus.Failed, DeliveryError.AgentBusy);
            return deliveryId;
        }

        _ = Task.Run(async () =>
        {
            try
            {
                await PerformDeliveryAsync(deliveryId, trimmed, session);
            }
            finally
            {
                _inFlight.TryRemove(session.Id, out _);
            }
        });

        return deliveryId;
    }

    public (DeliveryStatus Status, DeliveryError? Error)? Status(string deliveryId)
    {
        return _deliveryStore.Find(deliveryId, byDelivery: true);
    }

    private async Task PerformDeliveryAsync(string deliveryId, string text, AgentSession session)
    {
        if (!_adapters.TryGetValue(session.Provider, out var adapters) || adapters.Count == 0)
        {
            _deliveryStore.Update(deliveryId, DeliveryStatus.Failed, DeliveryError.ProviderUnsupported);
            return;
        }

        foreach (var adapter in adapters)
        {
            var result = await adapter.DeliverAsync(text, session).ConfigureAwait(false);
            if (result.Success)
            {
                _deliveryStore.Update(
                    deliveryId,
                    result.Status == DeliveryStatus.Delivered ? DeliveryStatus.Delivered : DeliveryStatus.Accepted,
                    null);
                return;
            }
        }

        _deliveryStore.Update(deliveryId, DeliveryStatus.Failed, DeliveryError.DeliveryFailed);
    }
}
