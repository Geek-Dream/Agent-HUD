using System.Security.Cryptography;
using System.Text;

namespace AgentHUD.Link;

public sealed class LinkPairingManager
{
    private const int MaxAttempts = 5;
    private static readonly TimeSpan SessionLifetime = TimeSpan.FromMinutes(2);
    private readonly object _gate = new();
    private readonly LinkDeviceStore _devices;
    private PairingSession? _current;
    private int _attempts;

    public LinkPairingManager(LinkDeviceStore devices)
    {
        _devices = devices;
    }

    public PairingSession CreateSession()
    {
        lock (_gate)
        {
            _current = new PairingSession(
                Guid.NewGuid().ToString("N"),
                Base64Url(RandomNumberGenerator.GetBytes(32)),
                RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6"),
                DateTimeOffset.Now.Add(SessionLifetime));
            _attempts = 0;
            return _current;
        }
    }

    public IssuedDeviceToken? CompleteQr(string? sessionId, string? secret, string? deviceName)
    {
        lock (_gate)
        {
            if (_current is null
                || !FixedEquals(_current.Id, sessionId)
                || !FixedEquals(_current.Secret, secret))
            {
                RegisterFailure();
                return null;
            }

            if (!IsCurrentSessionUsable())
            {
                return null;
            }

            var issued = _devices.IssueToken(deviceName);
            _current = null;
            _attempts = 0;
            return issued;
        }
    }

    public IssuedDeviceToken? CompleteCode(string? code, string? deviceName)
    {
        lock (_gate)
        {
            var normalized = new string((code ?? string.Empty).Where(char.IsDigit).ToArray());
            if (_current is null || !FixedEquals(_current.Code, normalized))
            {
                RegisterFailure();
                return null;
            }

            if (!IsCurrentSessionUsable())
            {
                return null;
            }

            var issued = _devices.IssueToken(deviceName);
            _current = null;
            _attempts = 0;
            return issued;
        }
    }

    private bool IsCurrentSessionUsable()
    {
        if (_current is not null && _current.ExpiresAt > DateTimeOffset.Now && _attempts < MaxAttempts)
        {
            return true;
        }
        _current = null;
        return false;
    }

    private void RegisterFailure()
    {
        _attempts++;
        if (_attempts >= MaxAttempts)
        {
            _current = null;
        }
    }

    private static bool FixedEquals(string? expected, string? actual)
    {
        if (expected is null || actual is null)
        {
            return false;
        }
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(expected),
            Encoding.UTF8.GetBytes(actual));
    }

    private static string Base64Url(byte[] bytes) =>
        Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
