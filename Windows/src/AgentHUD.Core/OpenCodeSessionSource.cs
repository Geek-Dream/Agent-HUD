using System.Text.Json;
using Microsoft.Data.Sqlite;

namespace AgentHUD.Core;

public static class OpenCodeSessionSource
{
    public static IReadOnlyList<AgentSession> Scan(
        string? databasePath,
        bool providerIsRunning,
        DateTimeOffset now)
    {
        var path = databasePath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            ".local",
            "share",
            "opencode",
            "opencode.db");
        if (!File.Exists(path))
        {
            return Array.Empty<AgentSession>();
        }

        try
        {
            using var connection = new SqliteConnection($"Data Source={path};Mode=ReadOnly");
            connection.Open();
            return HasTable(connection, "session_v2")
                ? ScanV2(connection, path, providerIsRunning, now)
                : ScanV1(connection, path, providerIsRunning, now);
        }
        catch (SqliteException)
        {
            return Array.Empty<AgentSession>();
        }
        catch (IOException)
        {
            return Array.Empty<AgentSession>();
        }
        catch (UnauthorizedAccessException)
        {
            return Array.Empty<AgentSession>();
        }
    }

    private static bool HasTable(SqliteConnection connection, string name)
    {
        using var command = connection.CreateCommand();
        command.CommandText =
            "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name=$name";
        command.Parameters.AddWithValue("$name", name);
        return Convert.ToInt64(command.ExecuteScalar() ?? 0L) > 0;
    }

    /// <summary>
    /// Legacy OpenCode layout: one row per session in <c>session</c>, with
    /// separate <c>message</c> and <c>part</c> tables.
    /// </summary>
    private static IReadOnlyList<AgentSession> ScanV1(
        SqliteConnection connection,
        string path,
        bool providerIsRunning,
        DateTimeOffset now)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, directory, title, time_created, time_updated
            FROM session
            WHERE time_updated >= $cutoff
            ORDER BY time_updated DESC
            LIMIT 36
            """;
        command.Parameters.AddWithValue("$cutoff", now.AddDays(-7).ToUnixTimeMilliseconds());

        var records = new List<(string ID, string Directory, string Title, long Created, long Updated)>();
        using (var reader = command.ExecuteReader())
        {
            while (reader.Read())
            {
                var id = reader.GetString(0);
                var directory = reader.GetString(1);
                var title = reader.IsDBNull(2) ? "OpenCode 会话" : reader.GetString(2);
                records.Add((id, directory, title, reader.GetInt64(3), reader.GetInt64(4)));
            }
        }

        var sessions = new List<AgentSession>();
        foreach (var value in records)
        {
            var record = new OpenCodeSessionRecord(
                value.ID,
                value.Directory,
                value.Title,
                DateTimeOffset.FromUnixTimeMilliseconds(value.Created),
                DateTimeOffset.FromUnixTimeMilliseconds(value.Updated),
                Events(connection, value.ID, "message", 200),
                Events(connection, value.ID, "part", 800));
            sessions.Add(OpenCodeAdapter.Parse(record, path, providerIsRunning, now));
        }
        return sessions;
    }

    /// <summary>
    /// OpenCode v2 layout: sessions live in <c>session_v2</c> and every message
    /// (user/assistant/tool output) is one row in <c>session_message</c> whose
    /// JSON payload embeds its own content parts. Querying the v1 table names
    /// against a v2 database throws "no such table", which the caller swallows —
    /// so OpenCode sessions silently never showed up on Windows.
    /// </summary>
    private static IReadOnlyList<AgentSession> ScanV2(
        SqliteConnection connection,
        string path,
        bool providerIsRunning,
        DateTimeOffset now)
    {
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, directory, title, time_created, time_updated
            FROM session_v2
            WHERE time_updated >= $cutoff
              AND IFNULL(time_archived, 0) = 0
              AND IFNULL(time_suspended, 0) = 0
            ORDER BY time_updated DESC
            LIMIT 36
            """;
        command.Parameters.AddWithValue("$cutoff", now.AddDays(-7).ToUnixTimeMilliseconds());

        var records = new List<(string ID, string Directory, string Title, long Created, long Updated)>();
        using (var reader = command.ExecuteReader())
        {
            while (reader.Read())
            {
                records.Add((
                    reader.GetString(0),
                    reader.IsDBNull(1) ? string.Empty : reader.GetString(1),
                    reader.IsDBNull(2) ? "OpenCode 会话" : reader.GetString(2),
                    reader.GetInt64(3),
                    reader.GetInt64(4)));
            }
        }

        var sessions = new List<AgentSession>();
        foreach (var value in records)
        {
            var events = V2Events(connection, value.ID);
            if (events.Messages.Count == 0)
            {
                continue;
            }
            var record = new OpenCodeSessionRecord(
                value.ID,
                value.Directory,
                value.Title,
                DateTimeOffset.FromUnixTimeMilliseconds(value.Created),
                DateTimeOffset.FromUnixTimeMilliseconds(value.Updated),
                events.Messages,
                events.Parts,
                events.IdleAt,
                events.IdleOutcome);
            sessions.Add(OpenCodeAdapter.Parse(record, path, providerIsRunning, now));
        }
        return sessions;
    }

    private static (List<OpenCodeEvent> Messages, List<OpenCodeEvent> Parts, DateTimeOffset? IdleAt, string? IdleOutcome)
        V2Events(SqliteConnection connection, string sessionId)
    {
        var messages = new List<OpenCodeEvent>();
        var parts = new List<OpenCodeEvent>();
        DateTimeOffset? idleAt = null;
        string? idleOutcome = null;

        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT id, type, time_created, data
            FROM session_message
            WHERE session_id = $sessionId
            ORDER BY seq DESC
            LIMIT 400
            """;
        command.Parameters.AddWithValue("$sessionId", sessionId);

        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            var id = reader.GetString(0);
            var type = reader.GetString(1);
            var date = DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(2));
            var data = reader.IsDBNull(3) ? "{}" : reader.GetString(3);
            try
            {
                using var document = JsonDocument.Parse(data);
                var root = document.RootElement;
                switch (type)
                {
                    case "user":
                        parts.Add(new OpenCodeEvent(
                            $"{id}:text",
                            date,
                            TextPart(root, "text"),
                            id));
                        messages.Add(new OpenCodeEvent(id, date, RoleMessage("user", root), null));
                        break;
                    case "assistant":
                        messages.Add(new OpenCodeEvent(id, date, RoleMessage("assistant", root), null));
                        if (JsonTools.Array(root, "content") is { } content)
                        {
                            var index = 0;
                            foreach (var part in content.EnumerateArray())
                            {
                                parts.Add(new OpenCodeEvent(
                                    $"{id}:part:{index++}",
                                    date,
                                    part.Clone(),
                                    id));
                            }
                        }
                        break;
                    case "idle":
                        // Authoritative "turn finished" marker; rows are read
                        // newest-first so the first hit is the latest turn.
                        idleAt ??= date;
                        idleOutcome ??= JsonTools.String(root, "outcome");
                        break;
                }
            }
            catch (JsonException)
            {
            }
        }
        return (messages, parts, idleAt, idleOutcome);
    }

    private static JsonElement RoleMessage(string role, JsonElement source)
    {
        var builder = new Dictionary<string, object?>();
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartObject();
            writer.WriteString("role", role);
            if (JsonTools.Object(source, "time") is { } time)
            {
                writer.WritePropertyName("time");
                time.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        using var document = JsonDocument.Parse(buffer.ToArray());
        return document.RootElement.Clone();
    }

    private static JsonElement TextPart(JsonElement source, string property)
    {
        var text = JsonTools.String(source, property) ?? string.Empty;
        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer))
        {
            writer.WriteStartObject();
            writer.WriteString("type", "text");
            writer.WriteString("text", text);
            writer.WriteEndObject();
        }
        using var document = JsonDocument.Parse(buffer.ToArray());
        return document.RootElement.Clone();
    }

    private static IReadOnlyList<OpenCodeEvent> Events(
        SqliteConnection connection,
        string sessionID,
        string table,
        int limit)
    {
        if (table is not ("message" or "part"))
        {
            return Array.Empty<OpenCodeEvent>();
        }

        using var command = connection.CreateCommand();
        var messageIDColumn = table == "part" ? "message_id" : "NULL";
        command.CommandText = $"""
            SELECT id, time_created, data, {messageIDColumn}
            FROM {table}
            WHERE session_id = $sessionId
            ORDER BY time_created DESC
            LIMIT {limit}
            """;
        command.Parameters.AddWithValue("$sessionId", sessionID);
        var events = new List<OpenCodeEvent>();
        using var reader = command.ExecuteReader();
        while (reader.Read())
        {
            try
            {
                using var document = JsonDocument.Parse(reader.GetString(2));
                events.Add(new OpenCodeEvent(
                    reader.GetString(0),
                    DateTimeOffset.FromUnixTimeMilliseconds(reader.GetInt64(1)),
                    document.RootElement.Clone(),
                    reader.IsDBNull(3) ? null : reader.GetString(3)));
            }
            catch (JsonException)
            {
            }
        }
        return events;
    }
}
