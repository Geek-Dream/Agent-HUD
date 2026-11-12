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
            using var command = connection.CreateCommand();
            command.CommandText = """
                SELECT id, directory, title, time_created, time_updated
                FROM session
                WHERE time_updated >= $cutoff
                ORDER BY time_updated DESC
                LIMIT 36
                """;
            command.Parameters.AddWithValue(
                "$cutoff",
                now.AddDays(-7).ToUnixTimeMilliseconds());

            var records = new List<(string ID, string Directory, string Title, long Created, long Updated)>();
            using var reader = command.ExecuteReader();
            while (reader.Read())
            {
                var id = reader.GetString(0);
                var directory = reader.GetString(1);
                var title = reader.IsDBNull(2) ? "OpenCode 会话" : reader.GetString(2);
                records.Add((id, directory, title, reader.GetInt64(3), reader.GetInt64(4)));
            }
            reader.Close();

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
                sessions.Add(OpenCodeAdapter.Parse(
                    record,
                    path,
                    providerIsRunning,
                    now));
            }
            return sessions;
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
