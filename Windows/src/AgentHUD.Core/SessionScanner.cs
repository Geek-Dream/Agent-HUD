using System.Collections.Concurrent;
using System.Diagnostics;

namespace AgentHUD.Core;

public sealed class SessionScanner
{
    private readonly Dictionary<string, (GitContext? Value, DateTimeOffset CheckedAt)> _gitCache =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gitLock = new();

    // Parsing a rollout file costs ~25 ms; the 3 s refresh loop re-parsed all of
    // them every single tick because nothing was cached. Keeping the parse
    // result until the file's size/mtime changes makes steady-state refreshes
    // ~10x cheaper, which is what makes the list feel live.
    private readonly ConcurrentDictionary<string, ParsedFile> _parseCache =
        new(StringComparer.OrdinalIgnoreCase);

    public DashboardSnapshot Scan(DateTimeOffset? nowValue = null)
    {
        var now = nowValue ?? DateTimeOffset.Now;
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var codexRoot = Path.Combine(home, ".codex", "sessions");
        var claudeRoot = Path.Combine(home, ".claude", "projects");
        var cutoff = now - TimeSpan.FromDays(7);
        var processes = ProcessPresence.Detect();

        var codexFiles = RecentFiles(codexRoot, cutoff, 36);
        var claudeFiles = RecentFiles(claudeRoot, cutoff, 36);
        var sessions = new List<AgentSession>();
        sessions.AddRange(OpenCodeSessionSource.Scan(
            databasePath: null,
            providerIsRunning: processes.OpenCode,
            now));

        var codexSessions = new AgentSession?[codexFiles.Count];
        var claudeSessions = new AgentSession?[claudeFiles.Count];

        // Files are independent, so parse them in parallel. Subagent transcripts
        // are passed in so a session whose parent log is idle still knows it has
        // children working.
        Parallel.For(0, codexFiles.Count, index =>
        {
            var file = codexFiles[index];
            var parsed = ParseCached(file, out var modified);
            if (parsed is not null)
            {
                codexSessions[index] = CodexAdapter.Parse(
                    parsed, file, modified, processes.Codex, now);
            }
        });

        Parallel.For(0, claudeFiles.Count, index =>
        {
            var file = claudeFiles[index];
            var parsed = ParseCached(file, out var modified);
            if (parsed is not null)
            {
                claudeSessions[index] = ClaudeAdapter.Parse(
                    parsed,
                    file,
                    modified,
                    processes.Claude,
                    now,
                    ReadSubagentRecords(file));
            }
        });

        sessions.AddRange(codexSessions.Where(session => session is not null)!);
        sessions.AddRange(claudeSessions.Where(session => session is not null)!);
        PruneParseCache(codexFiles, claudeFiles);

        var deduplicated = sessions
            .GroupBy(session => session.Id, StringComparer.Ordinal)
            .Select(group => group.OrderByDescending(session => session.LastActivityAt).First())
            .OrderBy(session => session.Status.SortRank())
            .ThenByDescending(session => session.LastActivityAt)
            .Take(24)
            .ToArray();

        var withGit = AttachGitInParallel(deduplicated);
        return new DashboardSnapshot(withGit, now);
    }

    private IReadOnlyList<System.Text.Json.JsonElement>? ParseCached(
        string path,
        out DateTimeOffset modified)
    {
        FileInfo info;
        try
        {
            info = new FileInfo(path);
            if (!info.Exists)
            {
                modified = DateTimeOffset.Now;
                return null;
            }
        }
        catch (IOException)
        {
            modified = DateTimeOffset.Now;
            return null;
        }

        modified = new DateTimeOffset(info.LastWriteTimeUtc, TimeSpan.Zero);
        var writeTicks = info.LastWriteTimeUtc.Ticks;
        var known = _parseCache.TryGetValue(path, out var cached);

        // Unchanged file: the cached parse is authoritative.
        if (known
            && cached!.Length == info.Length
            && cached.ModifiedUtcTicks == writeTicks)
        {
            return cached.Records;
        }

        try
        {
            // The active session log is appended to every few seconds and can
            // grow past 15 MB. Re-parsing it whole on every tick was the reason
            // the list felt seconds behind. Resume from the last complete line
            // and parse only what was appended.
            //
            // The stored offset is only trustworthy when the file actually grew:
            // a log that was rotated or truncated and then rewritten past the
            // old offset would silently skip the new head. Anything that is not
            // a clean append falls back to a full re-read.
            if (known
                && cached!.Offset > 0
                && info.Length > cached.Offset
                && writeTicks > cached.ModifiedUtcTicks)
            {
                var appended = JsonlReader.ReadFrom(path, cached.Offset, out var nextOffset);
                cached = new ParsedFile(
                    info.Length,
                    writeTicks,
                    appended.Count > 0 ? MergeRecords(cached.Records, appended) : cached.Records,
                    nextOffset);
                _parseCache[path] = cached;
                return cached.Records;
            }

            var records = JsonlReader.ReadFrom(path, 0, out var endOffset);
            cached = new ParsedFile(info.Length, writeTicks, records, endOffset);
            _parseCache[path] = cached;
            return records;
        }
        catch (IOException)
        {
            modified = DateTimeOffset.Now;
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            modified = DateTimeOffset.Now;
            return null;
        }
    }

    /// <summary>
    /// Subagent transcripts live next to their parent as
    /// <c>&lt;session&gt;/subagents/agent-*.jsonl</c> and inherit the parent's
    /// session id. Without them a parent that delegates work looks completed
    /// while its children are still running.
    /// </summary>
    private static IReadOnlyList<System.Text.Json.JsonElement>? ReadSubagentRecords(
        string parentPath)
    {
        var directory = Path.GetDirectoryName(parentPath);
        if (directory is null)
        {
            return null;
        }

        var subagentDirectory = Path.Combine(
            directory,
            Path.GetFileNameWithoutExtension(parentPath),
            "subagents");
        if (!Directory.Exists(subagentDirectory))
        {
            return null;
        }

        try
        {
            // Only the newest child matters for "is anything still running".
            var newest = Directory
                .EnumerateFiles(subagentDirectory, "*.jsonl")
                .Select(path => (Path: path, Modified: File.GetLastWriteTimeUtc(path)))
                .OrderByDescending(item => item.Modified)
                .FirstOrDefault();
            return newest.Path is null ? null : JsonlReader.Read(newest.Path);
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

    private void PruneParseCache(
        IReadOnlyList<string> codexFiles,
        IReadOnlyList<string> claudeFiles)
    {
        if (_parseCache.Count <= 96)
        {
            return;
        }

        var live = new HashSet<string>(codexFiles, StringComparer.OrdinalIgnoreCase);
        live.UnionWith(claudeFiles);
        foreach (var key in _parseCache.Keys)
        {
            if (!live.Contains(key))
            {
                _parseCache.TryRemove(key, out _);
            }
        }
    }

    private IReadOnlyList<AgentSession> AttachGitInParallel(
        IReadOnlyList<AgentSession> sessions)
    {
        var result = new AgentSession[sessions.Count];
        Parallel.For(0, sessions.Count, index =>
        {
            result[index] = sessions[index] with { Git = CachedGit(sessions[index].ProjectPath) };
        });
        return result;
    }

    private GitContext? CachedGit(string path)
    {
        lock (_gitLock)
        {
            if (_gitCache.TryGetValue(path, out var cached)
                && DateTimeOffset.Now - cached.CheckedAt
                    < (cached.Value is null ? TimeSpan.FromSeconds(30) : TimeSpan.FromSeconds(8)))
            {
                return cached.Value;
            }
        }

        var value = GitReader.Read(path);
        lock (_gitLock)
        {
            _gitCache[path] = (value, DateTimeOffset.Now);
        }
        return value;
    }

    private static IReadOnlyList<string> RecentFiles(
        string root,
        DateTimeOffset cutoff,
        int limit)
    {
        if (!Directory.Exists(root))
        {
            return Array.Empty<string>();
        }

        try
        {
            return Directory
                .EnumerateFiles(root, "*.jsonl", SearchOption.AllDirectories)
                .Take(4000)
                // Subagent transcripts carry the PARENT's session id but their
                // first row (`fork-context-ref`) has no sessionId field, so the
                // adapter fell back to the file name and each child surfaced as
                // a phantom extra session. They are read through their parent
                // instead (see ReadSubagentRecords).
                .Where(path => !IsSubagentTranscript(path))
                .Select(path => (Path: path, Modified: File.GetLastWriteTimeUtc(path)))
                .Where(item => new DateTimeOffset(item.Modified, TimeSpan.Zero) >= cutoff)
                .OrderByDescending(item => item.Modified)
                .Take(limit)
                .Select(item => item.Path)
                .ToArray();
        }
        catch (UnauthorizedAccessException)
        {
            return Array.Empty<string>();
        }
        catch (IOException)
        {
            return Array.Empty<string>();
        }
    }

    private static bool IsSubagentTranscript(string path) =>
        path.Replace('/', '\\').Contains(
            "\\subagents\\",
            StringComparison.OrdinalIgnoreCase);

    private sealed record ParsedFile(
        long Length,
        long ModifiedUtcTicks,
        IReadOnlyList<System.Text.Json.JsonElement> Records,
        long Offset);

    private static List<System.Text.Json.JsonElement> MergeRecords(
        IReadOnlyList<System.Text.Json.JsonElement> existing,
        IReadOnlyList<System.Text.Json.JsonElement> appended)
    {
        var merged = new List<System.Text.Json.JsonElement>(existing.Count + appended.Count);
        merged.AddRange(existing);
        merged.AddRange(appended);
        return merged;
    }

    private static class ProcessPresence
    {
        public static (bool Codex, bool Claude, bool OpenCode) Detect()
        {
            try
            {
                var names = Process.GetProcesses()
                    .Select(process =>
                    {
                        try
                        {
                            return process.ProcessName.ToLowerInvariant();
                        }
                        finally
                        {
                            process.Dispose();
                        }
                    })
                    .ToArray();
                return (
                    names.Any(name => name.Contains("codex", StringComparison.Ordinal)),
                    names.Any(name => name.Contains("claude", StringComparison.Ordinal)),
                    names.Any(name => name.Contains("opencode", StringComparison.Ordinal)));
            }
            catch
            {
                return (false, false, false);
            }
        }
    }
}
