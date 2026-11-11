using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;

namespace AgentHUD.Link;

public static class LinkNetwork
{
    public static IReadOnlyList<string> LocalIPv4Addresses()
    {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(item => item.OperationalStatus == OperationalStatus.Up)
            .SelectMany(item => item.GetIPProperties().UnicastAddresses)
            .Select(item => item.Address)
            .Where(address => address.AddressFamily == AddressFamily.InterNetwork)
            .Where(address => !IPAddress.IsLoopback(address))
            .Where(address => !address.ToString().StartsWith("169.254.", StringComparison.Ordinal))
            .Select(address => address.ToString())
            .Distinct(StringComparer.Ordinal)
            .OrderByDescending(IsPrivateLan)
            .ThenBy(address => address, StringComparer.Ordinal)
            .Take(6)
            .ToArray();
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
