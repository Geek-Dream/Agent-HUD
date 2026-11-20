using System.Text;
using System.Text.Json;

namespace AgentHUD.Core;

public static class JsonlReader
{
    public static IReadOnlyList<JsonElement> Read(string path)
    {
        var records = new List<JsonElement>();
        using var stream = Open(path);
        using var reader = new StreamReader(stream, Encoding.UTF8, true);
        while (reader.ReadLine() is { } line)
        {
            if (TryParse(line, out var record))
            {
                records.Add(record);
            }
        }
        return records;
    }

    /// <summary>
    /// Reads only the records appended since <paramref name="startOffset"/>.
    /// Returns the byte offset of the last complete line so the next call can
    /// resume there; a trailing partial line is left for the next read.
    /// </summary>
    public static IReadOnlyList<JsonElement> ReadFrom(string path, long startOffset, out long nextOffset)
    {
        var records = new List<JsonElement>();
        using var stream = Open(path);
        if (startOffset > 0 && startOffset <= stream.Length)
        {
            stream.Seek(startOffset, SeekOrigin.Begin);
        }
        else
        {
            startOffset = 0;
        }

        var buffer = new byte[64 * 1024];
        var pending = new MemoryStream();
        var offset = startOffset;
        var consumed = startOffset;

        int read;
        while ((read = stream.Read(buffer, 0, buffer.Length)) > 0)
        {
            var segmentStart = 0;
            for (var index = 0; index < read; index++)
            {
                if (buffer[index] != (byte)'\n')
                {
                    continue;
                }

                var lineLength = index - segmentStart;
                string line;
                if (pending.Length > 0)
                {
                    pending.Write(buffer, segmentStart, lineLength);
                    line = Encoding.UTF8.GetString(pending.GetBuffer(), 0, (int)pending.Length);
                    pending.SetLength(0);
                }
                else
                {
                    line = Encoding.UTF8.GetString(buffer, segmentStart, lineLength);
                }

                if (TryParse(line, out var record))
                {
                    records.Add(record);
                }
                segmentStart = index + 1;
                consumed = offset + index + 1;
            }

            if (segmentStart < read)
            {
                pending.Write(buffer, segmentStart, read - segmentStart);
            }
            offset += read;
        }

        // `consumed` only advances on newlines, so a half-written last line is
        // re-read (and re-parsed) on the next refresh instead of being lost.
        nextOffset = consumed;
        return records;
    }

    private static FileStream Open(string path) => new(
        path,
        FileMode.Open,
        FileAccess.Read,
        FileShare.ReadWrite | FileShare.Delete);

    private static bool TryParse(string line, out JsonElement record)
    {
        record = default;
        if (string.IsNullOrWhiteSpace(line))
        {
            return false;
        }

        try
        {
            using var document = JsonDocument.Parse(line);
            record = document.RootElement.Clone();
            return true;
        }
        catch (JsonException)
        {
            // Agent logs can be appended while being read. Ignore only the partial line.
            return false;
        }
    }
}
