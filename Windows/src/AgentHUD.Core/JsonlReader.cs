using System.Text;
using System.Text.Json;

namespace AgentHUD.Core;

public static class JsonlReader
{
    public static IReadOnlyList<JsonElement> Read(string path)
    {
        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream, Encoding.UTF8, true);
        var records = new List<JsonElement>();

        while (reader.ReadLine() is { } line)
        {
            if (string.IsNullOrWhiteSpace(line))
            {
                continue;
            }
            try
            {
                using var document = JsonDocument.Parse(line);
                records.Add(document.RootElement.Clone());
            }
            catch (JsonException)
            {
                // Agent logs can be appended while being read. Ignore only the partial line.
            }
        }

        return records;
    }
}
