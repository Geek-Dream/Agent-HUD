using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AgentHUD.Link;

public sealed class LinkDeviceStore
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    private readonly object _gate = new();
    private readonly string _devicesPath;
    private readonly Dictionary<string, LinkedDevice> _devices;
    private readonly byte[] _instanceKey;

    public LinkDeviceStore(string dataDirectory)
    {
        Directory.CreateDirectory(dataDirectory);
        _devicesPath = Path.Combine(dataDirectory, "devices.json");
        var identity = LoadIdentity(Path.Combine(dataDirectory, "identity.json"));
        InstanceId = identity.Id;
        InstanceName = identity.Name;
        _instanceKey = Convert.FromBase64String(identity.Key);
        _devices = LoadDevices();
    }

    public string InstanceId { get; }
    public string InstanceName { get; }

    public IReadOnlyList<LinkedDevice> Devices
    {
        get
        {
            lock (_gate)
            {
                return _devices.Values
                    .OrderByDescending(device => device.LastSeenAt ?? device.PairedAt)
                    .ToArray();
            }
        }
    }

    public IssuedDeviceToken IssueToken(string? deviceName)
    {
        var deviceId = Base64Url(RandomNumberGenerator.GetBytes(12));
        var token = Base64Url(RandomNumberGenerator.GetBytes(32));
        var device = new LinkedDevice(
            deviceId,
            NormalizeDeviceName(deviceName),
            Convert.ToBase64String(SHA256.HashData(Encoding.UTF8.GetBytes(token))),
            DateTimeOffset.Now,
            null);
        lock (_gate)
        {
            _devices.Add(device.Id, device);
            SaveDevices();
        }
        return new IssuedDeviceToken(device, token);
    }

    public bool Validate(string deviceId, string token)
    {
        if (string.IsNullOrWhiteSpace(deviceId) || string.IsNullOrWhiteSpace(token))
        {
            return false;
        }

        lock (_gate)
        {
            if (!_devices.TryGetValue(deviceId, out var device))
            {
                return false;
            }

            try
            {
                var expected = Convert.FromBase64String(device.TokenHash);
                var actual = SHA256.HashData(Encoding.UTF8.GetBytes(token));
                if (!CryptographicOperations.FixedTimeEquals(expected, actual))
                {
                    return false;
                }

                if (device.LastSeenAt is null
                    || DateTimeOffset.Now - device.LastSeenAt.Value > TimeSpan.FromMinutes(1))
                {
                    _devices[device.Id] = device with { LastSeenAt = DateTimeOffset.Now };
                    SaveDevices();
                }
                return true;
            }
            catch (FormatException)
            {
                return false;
            }
        }
    }

    public bool Revoke(string deviceId)
    {
        lock (_gate)
        {
            if (!_devices.Remove(deviceId))
            {
                return false;
            }
            SaveDevices();
            return true;
        }
    }

    public string PublicSessionId(string rawSessionId)
    {
        using var hmac = new HMACSHA256(_instanceKey);
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(rawSessionId));
        return Convert.ToHexString(hash.AsSpan(0, 16)).ToLowerInvariant();
    }

    private static string NormalizeDeviceName(string? deviceName)
    {
        var value = string.IsNullOrWhiteSpace(deviceName) ? "手机" : deviceName.Trim();
        return value.Length <= 80 ? value : value[..80];
    }

    private static Identity LoadIdentity(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                var identity = JsonSerializer.Deserialize<Identity>(File.ReadAllText(path), JsonOptions);
                if (identity is not null
                    && !string.IsNullOrWhiteSpace(identity.Id)
                    && !string.IsNullOrWhiteSpace(identity.Name)
                    && !string.IsNullOrWhiteSpace(identity.Key))
                {
                    return identity;
                }
            }
        }
        catch (Exception error) when (error is IOException or JsonException or FormatException)
        {
        }

        var created = new Identity(
            Guid.NewGuid().ToString("N"),
            Environment.MachineName,
            Convert.ToBase64String(RandomNumberGenerator.GetBytes(32)));
        var temporary = $"{path}.tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(created, JsonOptions));
        File.Move(temporary, path, true);
        return created;
    }

    private Dictionary<string, LinkedDevice> LoadDevices()
    {
        try
        {
            if (File.Exists(_devicesPath))
            {
                var devices = JsonSerializer.Deserialize<List<LinkedDevice>>(
                    File.ReadAllText(_devicesPath),
                    JsonOptions);
                return devices is null
                    ? new Dictionary<string, LinkedDevice>(StringComparer.Ordinal)
                    : devices.ToDictionary(device => device.Id, StringComparer.Ordinal);
            }
        }
        catch (Exception error) when (error is IOException or JsonException)
        {
        }
        return new Dictionary<string, LinkedDevice>(StringComparer.Ordinal);
    }

    private void SaveDevices()
    {
        var temporary = $"{_devicesPath}.tmp";
        File.WriteAllText(
            temporary,
            JsonSerializer.Serialize(_devices.Values.OrderBy(device => device.PairedAt).ToArray(), JsonOptions));
        File.Move(temporary, _devicesPath, true);
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private sealed record Identity(string Id, string Name, string Key);
}
