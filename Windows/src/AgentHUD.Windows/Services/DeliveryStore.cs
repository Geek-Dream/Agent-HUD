using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

public sealed class DeliveryStore
{
    private sealed record Entry(
        string DeliveryId,
        string ClientMessageId,
        string SessionPublicId,
        string TextHash,
        DeliveryStatus Status,
        DeliveryError? Error,
        DateTimeOffset CreatedAt,
        DateTimeOffset UpdatedAt);

    private readonly ConcurrentDictionary<string, Entry> _byDelivery = new();
    private readonly ConcurrentDictionary<string, string> _byClient = new();
    private readonly TimeSpan _ttl = TimeSpan.FromMinutes(5);

    public (string DeliveryId, DeliveryStatus Status, DeliveryError? Error)? Find(string clientMessageId)
    {
        Cleanup();
        if (!_byClient.TryGetValue(clientMessageId, out var deliveryId))
        {
            return null;
        }
        return _byDelivery.TryGetValue(deliveryId, out var entry)
            ? (entry.DeliveryId, entry.Status, entry.Error)
            : null;
    }

    public (DeliveryStatus Status, DeliveryError? Error)? Find(string deliveryId, bool byDelivery)
    {
        Cleanup();
        if (!_byDelivery.TryGetValue(deliveryId, out var entry))
        {
            return null;
        }
        return (entry.Status, entry.Error);
    }

    public string Create(string clientMessageId, string sessionPublicId, string text)
    {
        Cleanup();
        if (_byClient.TryGetValue(clientMessageId, out var existingId) &&
            _byDelivery.TryGetValue(existingId, out var existing))
        {
            return existing.DeliveryId;
        }
        var deliveryId = NewDeliveryId();
        var now = DateTimeOffset.Now;
        var entry = new Entry(
            deliveryId,
            clientMessageId,
            sessionPublicId,
            Hash(text),
            DeliveryStatus.Accepted,
            null,
            now,
            now);
        _byDelivery[deliveryId] = entry;
        _byClient[clientMessageId] = deliveryId;
        return deliveryId;
    }

    public void Update(string deliveryId, DeliveryStatus status, DeliveryError? error)
    {
        if (!_byDelivery.TryGetValue(deliveryId, out var entry))
        {
            return;
        }
        _byDelivery[deliveryId] = entry with
        {
            Status = status,
            Error = error,
            UpdatedAt = DateTimeOffset.Now
        };
    }

    private void Cleanup()
    {
        var cutoff = DateTimeOffset.Now - _ttl;
        foreach (var key in _byDelivery.Keys)
        {
            if (_byDelivery.TryGetValue(key, out var entry) && entry.UpdatedAt < cutoff)
            {
                _byDelivery.TryRemove(key, out _);
                _byClient.TryRemove(entry.ClientMessageId, out _);
            }
        }
    }

    private static string NewDeliveryId()
    {
        var bytes = RandomNumberGenerator.GetBytes(16);
        return Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');
    }

    private static string Hash(string text)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(text));
        return Convert.ToHexString(bytes).ToLowerInvariant();
    }
}
