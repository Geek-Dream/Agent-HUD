using System.Net;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Runtime.Versioning;

namespace AgentHUD.Link;

[SupportedOSPlatform("windows")]
public sealed record LinkCertificate(X509Certificate2 Certificate, string Fingerprint)
{
    public static LinkCertificate LoadOrCreate(string dataDirectory)
    {
        Directory.CreateDirectory(dataDirectory);
        var path = Path.Combine(dataDirectory, "certificate.dpapi");
        try
        {
            if (File.Exists(path))
            {
                var pfx = ProtectedData.Unprotect(
                    File.ReadAllBytes(path),
                    optionalEntropy: null,
                    DataProtectionScope.CurrentUser);
                var certificate = new X509Certificate2(pfx);
                if (certificate.NotAfter > DateTime.Now.AddDays(30))
                {
                    return new LinkCertificate(certificate, FingerprintOf(certificate));
                }
                certificate.Dispose();
            }
        }
        catch (Exception error) when (error is IOException or CryptographicException)
        {
        }

        using var rsa = RSA.Create(2048);
        var request = new CertificateRequest(
            "CN=AgentHUD Local",
            rsa,
            HashAlgorithmName.SHA256,
            RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(
            new X509EnhancedKeyUsageExtension(
                new OidCollection { new("1.3.6.1.5.5.7.3.1") },
                critical: false));
        var subjectNames = new SubjectAlternativeNameBuilder();
        subjectNames.AddDnsName("localhost");
        subjectNames.AddIpAddress(IPAddress.Loopback);
        foreach (var address in LinkNetwork.LocalIPv4Addresses())
        {
            subjectNames.AddIpAddress(IPAddress.Parse(address));
        }
        request.CertificateExtensions.Add(subjectNames.Build());

        using var generated = request.CreateSelfSigned(
            DateTimeOffset.Now.AddDays(-1),
            DateTimeOffset.Now.AddYears(5));
        var newPfx = generated.Export(X509ContentType.Pfx);
        var protectedPfx = ProtectedData.Protect(
            newPfx,
            optionalEntropy: null,
            DataProtectionScope.CurrentUser);
        var temporary = $"{path}.tmp";
        File.WriteAllBytes(temporary, protectedPfx);
        File.Move(temporary, path, true);

        var loaded = new X509Certificate2(newPfx);
        return new LinkCertificate(loaded, FingerprintOf(loaded));
    }

    private static string FingerprintOf(X509Certificate2 certificate) =>
        Convert.ToHexString(SHA256.HashData(certificate.RawData));
}
