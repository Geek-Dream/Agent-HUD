using System.Globalization;
using System.Text.Json;

namespace AgentHUD.Core;

public static class JsonTools
{
    public static string? String(JsonElement element, string property)
    {
        return TryGet(element, property, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;
    }

    public static bool? Bool(JsonElement element, string property)
    {
        return TryGet(element, property, out var value)
            && value.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? value.GetBoolean()
            : null;
    }

    public static JsonElement? Object(JsonElement element, string property)
    {
        return TryGet(element, property, out var value) && value.ValueKind == JsonValueKind.Object
            ? value
            : null;
    }

    public static JsonElement? Array(JsonElement element, string property)
    {
        return TryGet(element, property, out var value) && value.ValueKind == JsonValueKind.Array
            ? value
            : null;
    }

    public static bool TryGet(JsonElement element, string property, out JsonElement value)
    {
        if (element.ValueKind == JsonValueKind.Object && element.TryGetProperty(property, out value))
        {
            return true;
        }
        value = default;
        return false;
    }

    public static IReadOnlyList<string> CollectText(JsonElement? element)
    {
        if (element is null)
        {
            return System.Array.Empty<string>();
        }

        return CollectText(element.Value);
    }

    public static IReadOnlyList<string> CollectText(JsonElement element)
    {
        var values = new List<string>();
        CollectText(element, values);
        return values;
    }

    public static IReadOnlyList<string> FilePaths(JsonElement? element)
    {
        if (element is null)
        {
            return System.Array.Empty<string>();
        }

        var paths = new List<string>();
        CollectPaths(element.Value, paths, null);
        return TextTools.Unique(paths);
    }

    public static DateTimeOffset? Date(JsonElement? element, string property)
    {
        if (element is null || !TryGet(element.Value, property, out var value))
        {
            return null;
        }
        return ParseDate(value);
    }

    public static DateTimeOffset? ParseDate(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.String)
        {
            var text = value.GetString();
            if (DateTimeOffset.TryParse(
                    text,
                    CultureInfo.InvariantCulture,
                    DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal,
                    out var date))
            {
                return date;
            }
            if (double.TryParse(text, NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds))
            {
                return FromUnixSeconds(seconds);
            }
        }
        else if (value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var seconds))
        {
            return FromUnixSeconds(seconds);
        }
        return null;
    }

    private static DateTimeOffset FromUnixSeconds(double seconds)
    {
        if (seconds > 10_000_000_000)
        {
            seconds /= 1000;
        }
        try
        {
            return DateTimeOffset.FromUnixTimeMilliseconds((long)(seconds * 1000));
        }
        catch
        {
            return DateTimeOffset.MinValue;
        }
    }

    private static void CollectText(JsonElement element, List<string> values)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.String:
                var value = element.GetString();
                if (!string.IsNullOrWhiteSpace(value))
                {
                    values.Add(value);
                }
                break;
            case JsonValueKind.Array:
                foreach (var child in element.EnumerateArray())
                {
                    CollectText(child, values);
                }
                break;
            case JsonValueKind.Object:
                foreach (var property in new[] { "text", "content", "message", "output_text" })
                {
                    if (TryGet(element, property, out var child))
                    {
                        CollectText(child, values);
                    }
                }
                break;
        }
    }

    private static void CollectPaths(JsonElement element, List<string> paths, string? propertyName)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.String:
                if (propertyName is not null
                    && (propertyName.Contains("path", StringComparison.OrdinalIgnoreCase)
                        || propertyName.Contains("file", StringComparison.OrdinalIgnoreCase)))
                {
                    var value = element.GetString();
                    if (!string.IsNullOrWhiteSpace(value)
                        && (Path.IsPathRooted(value) || value.Contains('/') || value.Contains('\\')))
                    {
                        paths.Add(value);
                    }
                }
                break;
            case JsonValueKind.Array:
                foreach (var child in element.EnumerateArray())
                {
                    CollectPaths(child, paths, propertyName);
                }
                break;
            case JsonValueKind.Object:
                foreach (var property in element.EnumerateObject())
                {
                    CollectPaths(property.Value, paths, property.Name);
                }
                break;
        }
    }
}
