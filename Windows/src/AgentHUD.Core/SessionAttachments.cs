using System.Text.Json;

namespace AgentHUD.Core;

public static class SessionAttachmentParser
{
    private const int MaxAttachmentCount = 6;

    public static IReadOnlyList<SessionImageAttachment> CodexImages(JsonElement? content)
    {
        if (content is null || content.Value.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<SessionImageAttachment>();
        }

        var attachments = new List<SessionImageAttachment>();
        foreach (var part in content.Value.EnumerateArray())
        {
            if (attachments.Count >= MaxAttachmentCount || part.ValueKind != JsonValueKind.Object)
            {
                break;
            }

            var type = JsonTools.String(part, "type")?.ToLowerInvariant();
            if (type == "input_image")
            {
                var dataUrl = JsonTools.String(part, "image_url");
                if (IsValidImageDataUrl(dataUrl))
                {
                    attachments.Add(new SessionImageAttachment(
                        $"codex:image:{attachments.Count}",
                        null,
                        dataUrl,
                        null));
                }
            }
            else if (type == "local_image")
            {
                var path = JsonTools.String(part, "path");
                if (!string.IsNullOrWhiteSpace(path) && File.Exists(path))
                {
                    attachments.Add(new SessionImageAttachment(
                        $"codex:image:{attachments.Count}",
                        path,
                        null,
                        Path.GetFileName(path)));
                }
            }
        }
        return attachments;
    }

    public static IReadOnlyList<SessionImageAttachment> ClaudeImages(JsonElement? content)
    {
        if (content is null || content.Value.ValueKind != JsonValueKind.Array)
        {
            return Array.Empty<SessionImageAttachment>();
        }

        var attachments = new List<SessionImageAttachment>();
        foreach (var part in content.Value.EnumerateArray())
        {
            if (attachments.Count >= MaxAttachmentCount || part.ValueKind != JsonValueKind.Object)
            {
                break;
            }
            if (!string.Equals(JsonTools.String(part, "type"), "image", StringComparison.OrdinalIgnoreCase)
                || JsonTools.Object(part, "source") is not { } source)
            {
                continue;
            }

            var sourceType = JsonTools.String(source, "type");
            var mediaType = JsonTools.String(source, "media_type");
            var data = JsonTools.String(source, "data");
            if (string.Equals(sourceType, "base64", StringComparison.OrdinalIgnoreCase)
                && !string.IsNullOrWhiteSpace(mediaType)
                && mediaType.StartsWith("image/", StringComparison.OrdinalIgnoreCase)
                && !string.IsNullOrWhiteSpace(data))
            {
                attachments.Add(new SessionImageAttachment(
                    $"claude:image:{attachments.Count}",
                    null,
                    $"data:{mediaType};base64,{data}",
                    null));
            }
        }
        return attachments;
    }

    private static bool IsValidImageDataUrl(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return false;
        }
        return value.StartsWith("data:image/", StringComparison.OrdinalIgnoreCase)
            && value.Contains(";base64,", StringComparison.OrdinalIgnoreCase);
    }
}
