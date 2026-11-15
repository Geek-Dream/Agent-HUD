using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace AgentHUD.Link;

public static class LinkNetwork
{
    /// <summary>
    /// 本机可用于手机连接的 IPv4 地址。
    ///
    /// 组网（Tailscale / ZeroTier 一类）地址不在这个列表里——它们由
    /// <see cref="RemoteIPv4Addresses"/> 单独提供。原因是排序与截断会把它们
    /// 挤在后面、甚至截掉，而远程连接时手机恰恰最需要那个地址。
    /// </summary>
    public static IReadOnlyList<string> LocalIPv4Addresses()
    {
        return InterfaceIPv4Addresses()
            .Where(address => !IsCarrierGradeNAT(address))
            .OrderByDescending(IsPrivateLan)
            .ThenBy(address => address, StringComparer.Ordinal)
            .Take(6)
            .ToArray();
    }

    /// <summary>
    /// 远程组网（Tailscale / ZeroTier 一类）的 IPv4 地址。
    ///
    /// `100.64.0.0/10` 是 RFC 6598 的运营商级 NAT 保留段，Tailscale 复用它作为
    /// 虚拟网卡地址。这类地址在任何网络下都可达（只要对端在同一张私网里），
    /// 所以配对窗口要单独列出来——否则用户根本不知道该往手机里填什么。
    /// 与 macOS 端 `LinkCertificate.remoteIPv4Addresses()` 行为保持一致。
    /// </summary>
    public static IReadOnlyList<string> RemoteIPv4Addresses()
    {
        return InterfaceIPv4Addresses()
            .Where(IsCarrierGradeNAT)
            .ToArray();
    }

    private static IEnumerable<string> InterfaceIPv4Addresses()
    {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(item => item.OperationalStatus == OperationalStatus.Up)
            .SelectMany(item => item.GetIPProperties().UnicastAddresses)
            .Select(item => item.Address)
            .Where(address => address.AddressFamily == AddressFamily.InterNetwork)
            .Where(address => !IPAddress.IsLoopback(address))
            .Where(address => !address.ToString().StartsWith("169.254.", StringComparison.Ordinal))
            .Select(address => address.ToString())
            .Distinct(StringComparer.Ordinal);
    }

    /// <summary>
    /// 是否属于 RFC 6598 的 `100.64.0.0/10` 网段。
    ///
    /// 注意 `/10` 不是整字节边界：第二段落在 64–127 属于该网段，
    /// 所以 `100.63.x.x` 和 `100.128.x.x` 都不在范围内。
    /// </summary>
    public static bool IsCarrierGradeNAT(string value)
    {
        var parts = value.Split('.');
        if (parts.Length != 4 || !byte.TryParse(parts[0], out var first) || !byte.TryParse(parts[1], out var second))
        {
            return false;
        }
        return first == 100 && second is >= 64 and <= 127;
    }

    private static bool IsPrivateLan(string value)
    {
        var parts = value.Split('.');
        if (parts.Length != 4 || !byte.TryParse(parts[0], out var first) || !byte.TryParse(parts[1], out var second))
        {
            return false;
        }
        return first == 10
            || first == 192 && second == 168
            || first == 172 && second is >= 16 and <= 31;
    }
}
