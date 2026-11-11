namespace AgentHUD.Core;

public sealed class AIConfiguration
{
    public const string DefaultEndpoint = "https://cch.qcode.top:8443/v1";
    public const string DefaultModel = "kimi-k3.1-pro";

    public bool Enabled { get; set; }
    public string Endpoint { get; set; } = DefaultEndpoint;
    public string Model { get; set; } = DefaultModel;

    public bool IsUsable =>
        Enabled
        && !string.IsNullOrWhiteSpace(Model)
        && ChatCompletionsUri is not null;

    public Uri? ChatCompletionsUri
    {
        get
        {
            var normalized = (Endpoint ?? string.Empty).Trim().TrimEnd('/');
            if (!Uri.TryCreate(normalized, UriKind.Absolute, out var uri)
                || (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp))
            {
                return null;
            }

            if (uri.AbsolutePath.EndsWith("/chat/completions", StringComparison.OrdinalIgnoreCase))
            {
                return uri;
            }

            var path = uri.AbsolutePath.Trim('/');
            var builder = new UriBuilder(uri)
            {
                Path = path.Length == 0 ? "/chat/completions" : $"/{path}/chat/completions"
            };
            return builder.Uri;
        }
    }

    public AIConfiguration Clone() => new()
    {
        Enabled = Enabled,
        Endpoint = Endpoint,
        Model = Model
    };
}
