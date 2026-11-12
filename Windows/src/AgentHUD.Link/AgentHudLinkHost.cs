using System.Text.Json;
using System.Runtime.Versioning;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace AgentHUD.Link;

public sealed record LinkTitleRequest(string? Title);
public sealed record LinkImportantRequest(bool Important);

[SupportedOSPlatform("windows")]
public sealed class AgentHudLinkHost : IAsyncDisposable
{
    private readonly string _dataDirectory;
    private WebApplication? _app;
    private LinkDeviceStore? _devices;
    private LinkPairingManager? _pairing;
    private LinkCertificate? _certificate;
    private IMonitoringSnapshotSource? _snapshotSource;

    public AgentHudLinkHost(string? dataDirectory = null)
    {
        _dataDirectory = dataDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "AgentHUD",
            "link");
    }

    public bool IsRunning => _app is not null;
    public int Port { get; private set; }
    public string Fingerprint => _certificate?.Fingerprint ?? string.Empty;
    public LinkDeviceStore Devices => _devices ?? throw new InvalidOperationException("Link service is not running.");

    public async Task StartAsync(IMonitoringSnapshotSource snapshotSource)
    {
        if (_app is not null)
        {
            return;
        }

        _snapshotSource = snapshotSource;
        _devices = new LinkDeviceStore(_dataDirectory);
        _pairing = new LinkPairingManager(_devices);
        _certificate = LinkCertificate.LoadOrCreate(_dataDirectory);

        var builder = WebApplication.CreateBuilder(new WebApplicationOptions
        {
            EnvironmentName = Environments.Production
        });
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(options =>
        {
            options.Listen(
                System.Net.IPAddress.Any,
                0,
                listen => listen.UseHttps(_certificate.Certificate));
        });

        var app = builder.Build();
        app.Use(async (context, next) =>
        {
            if (context.Request.Path.StartsWithSegments("/v1/pair"))
            {
                await next();
                return;
            }

            if (!TryAuthenticate(context, out _, out _))
            {
                context.Response.StatusCode = StatusCodes.Status401Unauthorized;
                await context.Response.WriteAsJsonAsync(new { error = "unauthorized" });
                return;
            }
            await next();
        });

        app.MapPost("/v1/pair/complete", (PairCompleteRequest request) =>
        {
            var issued = _pairing.CompleteQr(request.SessionId, request.Secret, request.DeviceName);
            return issued is null
                ? Results.Json(new { error = "pairing_failed" }, statusCode: StatusCodes.Status401Unauthorized)
                : Results.Ok(CreatePairingResult(issued));
        });

        app.MapPost("/v1/pair/verify-code", (PairVerifyCodeRequest request) =>
        {
            var issued = _pairing.CompleteCode(request.Code, request.DeviceName);
            return issued is null
                ? Results.Json(new { error = "pairing_failed" }, statusCode: StatusCodes.Status401Unauthorized)
                : Results.Ok(CreatePairingResult(issued));
        });

        app.MapGet("/v1/status", () =>
        {
            var snapshot = _snapshotSource.GetMonitoringSnapshot();
            return Results.Ok(new
            {
                protocol = 1,
                instanceId = _devices.InstanceId,
                instanceName = _devices.InstanceName,
                capabilities = new[] { "monitor", "write", "prompt", "images" },
                revision = snapshot.Revision,
                scannedAt = snapshot.ScannedAt,
                serverTime = DateTimeOffset.Now,
                privacyMode = snapshot.PrivacyMode,
                fingerprint = Fingerprint,
                addresses = LinkNetwork.LocalIPv4Addresses(),
                port = Port
            });
        });

        app.MapGet("/v1/sessions", (string? status, string? provider, int? limit) =>
        {
            var snapshot = _snapshotSource.GetMonitoringSnapshot();
            var sessions = snapshot.Sessions.AsEnumerable();
            if (!string.IsNullOrWhiteSpace(status))
            {
                sessions = sessions.Where(session =>
                    session.Status.Equals(status, StringComparison.OrdinalIgnoreCase));
            }
            if (!string.IsNullOrWhiteSpace(provider))
            {
                sessions = sessions.Where(session =>
                    session.Provider.Equals(provider, StringComparison.OrdinalIgnoreCase));
            }

            var selected = sessions
                .Take(Math.Clamp(limit ?? 50, 1, 100))
                .Select(ToPublicSession)
                .ToArray();
            return Results.Ok(new
            {
                revision = snapshot.Revision,
                scannedAt = snapshot.ScannedAt,
                sessions = selected
            });
        });

        app.MapGet("/v1/sessions/{id}", (string id) =>
        {
            var snapshot = _snapshotSource.GetMonitoringSnapshot();
            var session = FindSession(snapshot, id);
            return session is null
                ? Results.NotFound(new { error = "session_not_found" })
                : Results.Ok(ToPublicSession(session));
        });

        app.MapPost("/v1/sessions/{id}/title", (string id, LinkTitleRequest request) =>
        {
            var snapshot = _snapshotSource.GetMonitoringSnapshot();
            var session = FindSession(snapshot, id);
            if (session is null)
            {
                return Results.NotFound(new { error = "session_not_found" });
            }

            var normalized = request.Title?.Trim() ?? string.Empty;
            if (normalized.Length > 72)
            {
                return Results.BadRequest(new { error = "title_too_long" });
            }

            if (!_snapshotSource.SetSessionTitle(
                    session.Id,
                    normalized.Length == 0 ? null : normalized))
            {
                return Results.Json(
                    new { error = "unsupported" },
                    statusCode: StatusCodes.Status501NotImplemented);
            }

            var updated = FindSession(_snapshotSource.GetMonitoringSnapshot(), id);
            return Results.Ok(new
            {
                id,
                title = updated?.Title ?? normalized,
                titleSource = updated?.TitleSource ?? "User",
                hasCustomTitle = updated?.HasCustomTitle ?? normalized.Length > 0
            });
        });

        app.MapPost("/v1/sessions/{id}/important", (string id, LinkImportantRequest request) =>
        {
            var snapshot = _snapshotSource.GetMonitoringSnapshot();
            var session = FindSession(snapshot, id);
            if (session is null)
            {
                return Results.NotFound(new { error = "session_not_found" });
            }

            if (!_snapshotSource.SetSessionImportant(session.Id, request.Important))
            {
                return Results.Json(
                    new { error = "unsupported" },
                    statusCode: StatusCodes.Status501NotImplemented);
            }

            var updated = FindSession(_snapshotSource.GetMonitoringSnapshot(), id);
            return Results.Ok(new
            {
                id,
                isImportant = updated?.IsImportant ?? request.Important
            });
        });

        app.MapGet("/v1/sessions/{id}/images/{index:int}", (string id, int index) =>
        {
            var snapshot = _snapshotSource.GetMonitoringSnapshot();
            var session = FindSession(snapshot, id);
            if (session is null)
            {
                return Results.NotFound(new { error = "session_not_found" });
            }

            var payload = _snapshotSource.GetPromptImage(session.Id, index);
            return payload is null
                ? Results.NotFound(new { error = "image_not_found" })
                : Results.File(payload.Data, payload.ContentType);
        });

        _app = app;
        await _app.StartAsync();
        var server = _app.Services.GetRequiredService<IServer>();
        var addressFeature = server.Features.Get<IServerAddressesFeature>()
            ?? throw new InvalidOperationException("Unable to determine the LAN listening port.");
        Port = addressFeature.Addresses
            .Select(address => new Uri(address).Port)
            .FirstOrDefault();
        if (Port == 0)
        {
            throw new InvalidOperationException("Unable to determine the LAN listening port.");
        }
    }

    public PairingOffer CreatePairingOffer()
    {
        if (_app is null || _pairing is null || _devices is null)
        {
            throw new InvalidOperationException("Link service is not running.");
        }

        var session = _pairing.CreateSession();
        var addresses = LinkNetwork.LocalIPv4Addresses();
        var payload = JsonSerializer.Serialize(new
        {
            v = 1,
            instanceId = _devices.InstanceId,
            instanceName = _devices.InstanceName,
            addresses,
            port = Port,
            fingerprint = Fingerprint,
            sessionId = session.Id,
            secret = session.Secret,
            expiresAt = session.ExpiresAt
        });
        return new PairingOffer(
            session.Code,
            payload,
            session.ExpiresAt,
            addresses,
            Port,
            Fingerprint);
    }

    public IReadOnlyList<LinkedDevice> RevokeDevice(string deviceId)
    {
        Devices.Revoke(deviceId);
        return Devices.Devices;
    }

    public async ValueTask DisposeAsync()
    {
        if (_app is not null)
        {
            await _app.StopAsync();
            await _app.DisposeAsync();
            _app = null;
        }
        _certificate?.Certificate.Dispose();
        _certificate = null;
        _snapshotSource = null;
    }

    private PairingResult CreatePairingResult(IssuedDeviceToken issued) => new(
        issued.Device.Id,
        issued.Token,
        _devices!.InstanceId,
        _devices.InstanceName,
        1,
        new[] { "monitor", "write", "prompt", "images" },
        Fingerprint,
        LinkNetwork.LocalIPv4Addresses(),
        Port);

    private MonitoringSessionSnapshot ToPublicSession(MonitoringSessionSnapshot session) =>
        session with { Id = _devices!.PublicSessionId(session.Id) };

    private MonitoringSessionSnapshot? FindSession(MonitoringSnapshot snapshot, string publicId) =>
        snapshot.Sessions.FirstOrDefault(item =>
            _devices!.PublicSessionId(item.Id).Equals(publicId, StringComparison.OrdinalIgnoreCase));

    private bool TryAuthenticate(HttpContext context, out string deviceId, out string token)
    {
        deviceId = string.Empty;
        token = string.Empty;
        var header = context.Request.Headers.Authorization.ToString();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var credential = header[7..].Trim();
        var separator = credential.IndexOf('.');
        if (separator <= 0 || separator == credential.Length - 1)
        {
            return false;
        }

        deviceId = credential[..separator];
        token = credential[(separator + 1)..];
        return _devices!.Validate(deviceId, token);
    }
}
