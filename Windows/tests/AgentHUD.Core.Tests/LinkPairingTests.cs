using AgentHUD.Link;
using Xunit;

namespace AgentHUD.Core.Tests;

public sealed class LinkPairingTests
{
    [Fact]
    public void QrPairingIssuesMonitorTokenOnlyOnce()
    {
        using var directory = new TestDirectory();
        var store = new LinkDeviceStore(directory.Path);
        var manager = new LinkPairingManager(store);
        var session = manager.CreateSession();

        var issued = manager.CompleteQr(session.Id, session.Secret, "测试手机");

        Assert.NotNull(issued);
        Assert.Equal("测试手机", issued.Device.Name);
        Assert.True(store.Validate(issued.Device.Id, issued.Token));
        Assert.Null(manager.CompleteQr(session.Id, session.Secret, "另一台手机"));
        Assert.True(store.Revoke(issued.Device.Id));
        Assert.False(store.Validate(issued.Device.Id, issued.Token));
    }

    [Fact]
    public void CodePairingRejectsTooManyFailures()
    {
        using var directory = new TestDirectory();
        var store = new LinkDeviceStore(directory.Path);
        var manager = new LinkPairingManager(store);
        var session = manager.CreateSession();

        for (var attempt = 0; attempt < 5; attempt++)
        {
            Assert.Null(manager.CompleteCode("999999", "测试手机"));
        }
        Assert.Null(manager.CompleteCode(session.Code, "测试手机"));
    }

    [Fact]
    public void CodePairingAcceptsFormattedCode()
    {
        using var directory = new TestDirectory();
        var store = new LinkDeviceStore(directory.Path);
        var manager = new LinkPairingManager(store);
        var session = manager.CreateSession();
        var formatted = $"{session.Code[..3]}-{session.Code[3..]}";

        var issued = manager.CompleteCode(formatted, "测试手机");

        Assert.NotNull(issued);
        Assert.True(store.Validate(issued.Device.Id, issued.Token));
    }

    [Fact]
    public void IdentityAndPublicSessionIdsSurviveReload()
    {
        using var directory = new TestDirectory();
        var store = new LinkDeviceStore(directory.Path);
        var instanceId = store.InstanceId;
        var first = store.PublicSessionId("session-one");
        var second = store.PublicSessionId("session-two");

        var reloaded = new LinkDeviceStore(directory.Path);

        Assert.Equal(instanceId, reloaded.InstanceId);
        Assert.Equal(first, reloaded.PublicSessionId("session-one"));
        Assert.NotEqual(first, second);
        Assert.Equal(32, first.Length);
    }

    [Fact]
    public void CertificateFingerprintIsStableAcrossReload()
    {
        using var directory = new TestDirectory();
        var first = LinkCertificate.LoadOrCreate(directory.Path);
        var second = LinkCertificate.LoadOrCreate(directory.Path);
        try
        {
            Assert.Equal(first.Fingerprint, second.Fingerprint);
            Assert.Equal(64, first.Fingerprint.Length);
        }
        finally
        {
            first.Certificate.Dispose();
            second.Certificate.Dispose();
        }
    }

    private sealed class TestDirectory : IDisposable
    {
        public TestDirectory()
        {
            Path = System.IO.Path.Combine(
                System.IO.Path.GetTempPath(),
                $"AgentHUD-LinkTests-{Guid.NewGuid():N}");
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
