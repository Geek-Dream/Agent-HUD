using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

public static class AgentHudLinkRuntime
{
    private static readonly object Gate = new();
    private static AgentHudLinkHost? _host;
    private static IMonitoringSnapshotSource? _source;

    public static string? LastError { get; private set; }
    public static bool IsRunning => _host?.IsRunning == true;
    public static string? InstanceName => _host?.Devices.InstanceName;
    public static IReadOnlyList<LinkedDevice> Devices =>
        IsRunning ? _host!.Devices.Devices : Array.Empty<LinkedDevice>();

    public static async Task StartAsync(IMonitoringSnapshotSource source)
    {
        AgentHudLinkHost? candidate = null;
        try
        {
            lock (Gate)
            {
                if (_host is not null)
                {
                    return;
                }
                _source = source;
                candidate = new AgentHudLinkHost();
                _host = candidate;
            }

            await candidate.StartAsync(source);
            LastError = null;
        }
        catch (Exception error)
        {
            LastError = error.Message;
            if (candidate is not null)
            {
                await candidate.DisposeAsync();
            }
            lock (Gate)
            {
                _host = null;
            }
        }
    }

    public static async Task RestartAsync()
    {
        var source = _source;
        if (source is null)
        {
            return;
        }
        await StopAsync();
        await StartAsync(source);
    }

    public static PairingOffer CreatePairingOffer()
    {
        if (!IsRunning)
        {
            throw new InvalidOperationException(LastError ?? "局域网服务尚未启动。");
        }
        return _host!.CreatePairingOffer();
    }

    public static IReadOnlyList<LinkedDevice> RevokeDevice(string deviceId)
    {
        return IsRunning ? _host!.RevokeDevice(deviceId) : Devices;
    }

    public static bool SetConversationEnabled(string deviceId, bool enabled)
    {
        return IsRunning && _host!.SetConversationEnabled(deviceId, enabled);
    }

    public static string ServiceAddressText()
    {
        if (!IsRunning)
        {
            return LastError ?? "局域网服务尚未启动";
        }
        var addresses = LinkNetwork.LocalIPv4Addresses();
        return addresses.Count == 0
            ? "未发现可用的局域网 IPv4 地址"
            : $"监听端口 {_host!.Port} · {string.Join(" / ", addresses)}";
    }

    public static async Task StopAsync()
    {
        AgentHudLinkHost? host;
        lock (Gate)
        {
            host = _host;
            _host = null;
        }
        if (host is not null)
        {
            await host.DisposeAsync();
        }
    }
}
