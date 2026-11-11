using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace AgentHUD.Core;

public sealed record AITitleRequest(
    string SessionId,
    string Prompt,
    string ProjectName,
    IReadOnlyList<SessionImageAttachment> Images);

public sealed class AITitleService : IDisposable
{
    private const int MaximumImageBytes = 8 * 1024 * 1024;
    private readonly HttpClient _httpClient;
    private readonly Dictionary<string, string> _titles = new(StringComparer.Ordinal);
    private readonly Dictionary<string, DateTimeOffset> _failures = new(StringComparer.Ordinal);
    private readonly object _lock = new();

    public AITitleService(HttpClient? httpClient = null)
    {
        _httpClient = httpClient ?? new HttpClient();
        _httpClient.Timeout = TimeSpan.FromSeconds(28);
    }

    public async Task<string> GetTitleAsync(
        AITitleRequest request,
        AIConfiguration configuration,
        string apiKey,
        CancellationToken cancellationToken)
    {
        if (!configuration.IsUsable || string.IsNullOrWhiteSpace(apiKey))
        {
            throw new InvalidOperationException("AI 标题配置不完整。");
        }

        var imageDataUrls = request.Images
            .Take(6)
            .Select(ToDataUrl)
            .Where(value => value is not null)
            .Cast<string>()
            .ToArray();
        var prompt = TextTools.UserPromptText(request.Prompt, 4000).Trim();
        if (prompt.Length == 0 && imageDataUrls.Length == 0)
        {
            throw new InvalidOperationException("当前会话没有可总结的用户输入。");
        }

        var cacheKey = Hash(string.Join(
            "\u001E",
            request.SessionId,
            prompt,
            request.ProjectName,
            configuration.ChatCompletionsUri?.AbsoluteUri ?? string.Empty,
            configuration.Model,
            string.Join("\u001F", imageDataUrls)));

        lock (_lock)
        {
            if (_titles.TryGetValue(cacheKey, out var cached))
            {
                return cached;
            }
            if (_failures.TryGetValue(cacheKey, out var retryAt) && retryAt > DateTimeOffset.Now)
            {
                throw new InvalidOperationException("AI 请求正在退避。");
            }
        }

        try
        {
            var title = await RequestTitleAsync(
                request,
                prompt,
                imageDataUrls,
                configuration,
                apiKey,
                cancellationToken);
            lock (_lock)
            {
                _titles[cacheKey] = title;
                _failures.Remove(cacheKey);
            }
            return title;
        }
        catch
        {
            lock (_lock)
            {
                _failures[cacheKey] = DateTimeOffset.Now.AddMinutes(5);
            }
            throw;
        }
    }

    public async Task TestConnectionAsync(
        AIConfiguration configuration,
        string apiKey,
        CancellationToken cancellationToken)
    {
        var request = new AITitleRequest(
            $"connection-test-{Guid.NewGuid()}",
            "请只回复：连接正常",
            string.Empty,
            Array.Empty<SessionImageAttachment>());
        _ = await GetTitleAsync(request, configuration, apiKey, cancellationToken);
    }

    public void ClearCache()
    {
        lock (_lock)
        {
            _titles.Clear();
            _failures.Clear();
        }
    }

    public void Dispose() => _httpClient.Dispose();

    private async Task<string> RequestTitleAsync(
        AITitleRequest request,
        string prompt,
        IReadOnlyList<string> imageDataUrls,
        AIConfiguration configuration,
        string apiKey,
        CancellationToken cancellationToken)
    {
        var userContent = new List<object>
        {
            new
            {
                type = "text",
                text = string.IsNullOrWhiteSpace(request.ProjectName)
                    ? $"用户最近一次有效输入：\n{prompt}"
                    : $"项目名称（仅供理解，不要写进标题）：{request.ProjectName}\n用户最近一次有效输入：\n{prompt}"
            }
        };
        userContent.AddRange(imageDataUrls.Select(dataUrl => (object)new
        {
            type = "image_url",
            image_url = new { url = dataUrl }
        }));

        var payload = new
        {
            model = configuration.Model.Trim(),
            max_tokens = 512,
            stream = false,
            messages = new object[]
            {
                new
                {
                    role = "system",
                    content = """
                        你是任务标题总结器。根据用户最近一次输入和图片，用大白话概括用户真正想做什么。
                        只输出一个中文标题，不要解释，不要引号、Markdown、句号或冒号。
                        标题约 6 到 16 个汉字；不要照抄原句；不要写项目名；不要使用“处理某项目任务”这类泛化模板。
                        """
                },
                new
                {
                    role = "user",
                    content = userContent
                }
            }
        };

        using var httpRequest = new HttpRequestMessage(
            HttpMethod.Post,
            configuration.ChatCompletionsUri);
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue(
            "Bearer",
            apiKey.Trim());
        httpRequest.Content = new StringContent(
            JsonSerializer.Serialize(payload),
            Encoding.UTF8,
            "application/json");

        using var response = await _httpClient.SendAsync(
            httpRequest,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken);
        response.EnsureSuccessStatusCode();
        var responseBody = await response.Content.ReadAsStringAsync(cancellationToken);
        var rawTitle = ParseTitle(responseBody);
        return SanitizeTitle(rawTitle, prompt)
            ?? throw new InvalidOperationException("AI 返回的标题不可用。");
    }

    private static string ParseTitle(string json)
    {
        using var document = JsonDocument.Parse(json);
        if (!document.RootElement.TryGetProperty("choices", out var choices)
            || choices.ValueKind != JsonValueKind.Array
            || choices.GetArrayLength() == 0
            || !choices[0].TryGetProperty("message", out var message)
            || !message.TryGetProperty("content", out var content))
        {
            throw new InvalidOperationException("AI 返回内容无法解析。");
        }

        return string.Join("\n", JsonTools.CollectText(content));
    }

    private static string? SanitizeTitle(string raw, string originalPrompt)
    {
        var firstLine = raw.Split('\n')
            .Select(TextTools.NormalizeWhitespace)
            .FirstOrDefault(line => line.Length > 0) ?? string.Empty;
        var title = firstLine
            .Replace("```", string.Empty)
            .Replace("**", string.Empty)
            .Replace("`", string.Empty)
            .Trim()
            .Trim('"', '\'', '“', '”', '‘', '’', '。', '.', ':', '：');
        foreach (var prefix in new[] { "标题：", "标题:", "任务标题：", "任务标题:", "总结：", "总结:" })
        {
            if (title.StartsWith(prefix, StringComparison.Ordinal))
            {
                title = title[prefix.Length..].Trim();
            }
        }

        if (title.Length is < 2 or > 36
            || TextTools.IsContinuationPrompt(title)
            || title.Contains("http://", StringComparison.OrdinalIgnoreCase)
            || title.Contains("https://", StringComparison.OrdinalIgnoreCase)
            || title.Contains('\\')
            || title.Contains('/')
            || title.Contains("处理项目任务", StringComparison.Ordinal))
        {
            return null;
        }

        var normalizedPrompt = TextTools.NormalizeWhitespace(originalPrompt);
        if (normalizedPrompt.Length > title.Length + 8
            && normalizedPrompt.Contains(title, StringComparison.Ordinal))
        {
            return null;
        }
        return title;
    }

    private static string? ToDataUrl(SessionImageAttachment attachment)
    {
        if (!string.IsNullOrWhiteSpace(attachment.DataUrl))
        {
            return attachment.DataUrl;
        }
        if (string.IsNullOrWhiteSpace(attachment.LocalPath) || !File.Exists(attachment.LocalPath))
        {
            return null;
        }
        try
        {
            var info = new FileInfo(attachment.LocalPath);
            if (info.Length <= 0 || info.Length > MaximumImageBytes)
            {
                return null;
            }
            var mediaType = Path.GetExtension(info.FullName).ToLowerInvariant() switch
            {
                ".png" => "image/png",
                ".gif" => "image/gif",
                ".webp" => "image/webp",
                _ => "image/jpeg"
            };
            return $"data:{mediaType};base64,{Convert.ToBase64String(File.ReadAllBytes(info.FullName))}";
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    private static string Hash(string value)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(value));
        return Convert.ToHexString(bytes);
    }
}
