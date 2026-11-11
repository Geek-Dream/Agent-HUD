using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text.Json;
using AgentHUD.Link;
using Xunit;

namespace AgentHUD.Core.Tests;

[SupportedOSPlatform("windows")]
public sealed class LinkHostTests
{
    [Fact]
    public async Task PairingAndMonitoringEndpointsWorkOverHttps()
    {
        using var directory = new TestDirectory();
        var host = new AgentHudLinkHost(directory.Path);
        await host.StartAsync(new FakeSnapshotSource());
        try
        {
            using var handler = new HttpClientHandler
            {
                ServerCertificateCustomValidationCallback = (_, certificate, _, _) =>
                    certificate is not null
                    && Convert.ToHexString(SHA256.HashData(certificate.RawData)) == host.Fingerprint
            };
            using var client = new HttpClient(handler)
            {
                BaseAddress = new Uri($"https://127.0.0.1:{host.Port}")
            };

            var unauthorized = await client.GetAsync("/v1/status");
            Assert.Equal(HttpStatusCode.Unauthorized, unauthorized.StatusCode);

            var offer = host.CreatePairingOffer();
            var payload = JsonDocument.Parse(offer.Payload).RootElement;
            var pairingResponse = await client.PostAsJsonAsync("/v1/pair/complete", new
            {
                sessionId = payload.GetProperty("sessionId").GetString(),
                secret = payload.GetProperty("secret").GetString(),
                deviceName = "集成测试手机"
            });
            Assert.Equal(HttpStatusCode.OK, pairingResponse.StatusCode);
            var pairing = JsonDocument.Parse(await pairingResponse.Content.ReadAsStringAsync()).RootElement;
            var deviceId = pairing.GetProperty("deviceId").GetString()!;
            var token = pairing.GetProperty("token").GetString()!;
            client.DefaultRequestHeaders.Authorization =
                new AuthenticationHeaderValue("Bearer", $"{deviceId}.{token}");

            var statusResponse = await client.GetAsync("/v1/status");
            Assert.Equal(HttpStatusCode.OK, statusResponse.StatusCode);
            var status = JsonDocument.Parse(await statusResponse.Content.ReadAsStringAsync()).RootElement;
            Assert.Equal(7, status.GetProperty("revision").GetInt64());
            Assert.Equal("monitor", status.GetProperty("capabilities")[0].GetString());

            var sessionsResponse = await client.GetAsync("/v1/sessions");
            Assert.Equal(HttpStatusCode.OK, sessionsResponse.StatusCode);
            var body = await sessionsResponse.Content.ReadAsStringAsync();
            var sessions = JsonDocument.Parse(body).RootElement.GetProperty("sessions");
            Assert.Single(sessions.EnumerateArray());
            Assert.Equal(32, sessions[0].GetProperty("id").GetString()!.Length);
            Assert.DoesNotContain("raw/session/path", body, StringComparison.Ordinal);
            Assert.DoesNotContain("ProjectPath", body, StringComparison.OrdinalIgnoreCase);
            Assert.DoesNotContain("LatestUserPrompt", body, StringComparison.OrdinalIgnoreCase);
        }
        finally
        {
            await host.DisposeAsync();
        }
    }

    private sealed class FakeSnapshotSource : IMonitoringSnapshotSource
    {
        public MonitoringSnapshot GetMonitoringSnapshot()
        {
            var now = DateTimeOffset.Now;
            var session = new MonitoringSessionSnapshot(
                "raw/session/path",
                "Codex",
                "Working",
                "High",
                "测试任务",
                "Demo",
                "正在执行测试",
                new[] { "Program.cs" },
                now.AddMinutes(-3),
                now,
                null,
                true,
                "main",
                1,
                2,
                0,
                "测试摘要");
            return new MonitoringSnapshot(7, now, false, new[] { session });
        }
    }

    private sealed class TestDirectory : IDisposable
    {
        public TestDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"AgentHUD-LinkHostTests-{Guid.NewGuid():N}");
            Directory.CreateDirectory(Path);
        }

        public string Path { get; }

        public void Dispose()
        {
            if (Directory.Exists(Path))
            {
                Directory.Delete(Path, recursive: true);
            }
        }
    }
}
