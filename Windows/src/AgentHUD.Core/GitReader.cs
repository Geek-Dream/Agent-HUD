using System.Diagnostics;

namespace AgentHUD.Core;

public static class GitReader
{
    public static GitContext? Read(string projectPath)
    {
        if (string.IsNullOrWhiteSpace(projectPath) || !Directory.Exists(projectPath))
        {
            return null;
        }

        var root = Run(projectPath, "rev-parse", "--show-toplevel")?.Trim();
        if (string.IsNullOrWhiteSpace(root))
        {
            return null;
        }

        var branch = Run(projectPath, "branch", "--show-current")?.Trim();
        if (string.IsNullOrWhiteSpace(branch))
        {
            branch = "detached";
        }

        var status = Run(projectPath, "status", "--porcelain") ?? string.Empty;
        var changedFiles = status
            .Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Length;
        var insertions = 0;
        var deletions = 0;
        var numstat = Run(projectPath, "diff", "--numstat") ?? string.Empty;
        foreach (var line in numstat.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = line.Split('\t');
            if (parts.Length < 2)
            {
                continue;
            }
            if (int.TryParse(parts[0], out var added))
            {
                insertions += added;
            }
            if (int.TryParse(parts[1], out var removed))
            {
                deletions += removed;
            }
        }

        return new GitContext(root, branch, changedFiles, insertions, deletions, changedFiles > 0);
    }

    private static string? Run(string workingDirectory, params string[] arguments)
    {
        try
        {
            var startInfo = new ProcessStartInfo
            {
                FileName = "git",
                WorkingDirectory = workingDirectory,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            foreach (var argument in arguments)
            {
                startInfo.ArgumentList.Add(argument);
            }

            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return null;
            }
            if (!process.WaitForExit(1500))
            {
                process.Kill(true);
                return null;
            }
            return process.StandardOutput.ReadToEnd();
        }
        catch
        {
            return null;
        }
    }
}
