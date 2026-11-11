using System.Diagnostics;

namespace AgentHUD.Core;

public sealed class SessionScanner
{
    private readonly Dictionary<string, (GitContext? Value, DateTimeOffset CheckedAt)> _gitCache =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly object _gitLock = new();

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

        foreach (var file in codexFiles)
        {
            try
            {
                var records = JsonlReader.Read(file);
                var modified = new DateTimeOffset(File.GetLastWriteTimeUtc(file), TimeSpan.Zero);
                var session = CodexAdapter.Parse(records, file, modified, processes.Codex, now);
                if (session is not null)
                {
                    sessions.Add(session);
                }
            }
            catch (IOException)
            {
                // A log can be rotated while scanning; the next refresh will retry it.
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        foreach (var file in claudeFiles)
        {
            try
            {
                var records = JsonlReader.Read(file);
                var modified = new DateTimeOffset(File.GetLastWriteTimeUtc(file), TimeSpan.Zero);
                var session = ClaudeAdapter.Parse(records, file, modified, processes.Claude, now);
                if (session is not null)
                {
                    sessions.Add(session);
                }
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }

        var deduplicated = sessions
            .GroupBy(session => session.Id, StringComparer.Ordinal)
            .Select(group => group.OrderByDescending(session => session.LastActivityAt).First())
            .OrderBy(session => session.Status.SortRank())
            .ThenByDescending(session => session.LastActivityAt)
            .Take(24)
            .Select(AttachGit)
            .ToArray();

        return new DashboardSnapshot(deduplicated, now);
    }

    private AgentSession AttachGit(AgentSession session)
    {
        var value = CachedGit(session.ProjectPath);
        return session with { Git = value };
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

    private static class ProcessPresence
    {
        public static (bool Codex, bool Claude) Detect()
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
                    names.Any(name => name.Contains("claude", StringComparison.Ordinal)));
            }
            catch
            {
                return (false, false);
            }
        }
    }
}
