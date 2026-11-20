using System.Diagnostics;

namespace AgentHUD.Windows.Services;

internal static class AgentExecutableFinder
{
    public static string? FindCodex() => Find("codex.exe", "@openai", "codex");

    public static string? FindOpenCode() => Find("opencode.exe", "@opencode", "cli");

    public static string? FindClaude() => Find("claude.exe", "@anthropic-ai", "claude-code");

    private static string? Find(string executable, string scope, string package)
    {
        foreach (var directory in Directories())
        {
            var direct = Path.Combine(directory, executable);
            if (File.Exists(direct)) return direct;
        }
        // npm 的 .cmd 启动器不适合作为无窗口子进程，直接定位包内的原生可执行文件。
        var roots = new[] { Environment.GetEnvironmentVariable("APPDATA"), Environment.GetEnvironmentVariable("LOCALAPPDATA") };
        foreach (var root in roots)
        {
            if (string.IsNullOrWhiteSpace(root)) continue;
            var packageRoot = Path.Combine(root, "npm", "node_modules", scope, package);
            if (!Directory.Exists(packageRoot)) continue;
            var candidates = Directory.EnumerateFiles(packageRoot, executable, SearchOption.AllDirectories);
            var match = candidates.FirstOrDefault();
            if (match is not null) return match;
        }
        return null;
    }

    private static IEnumerable<string> Directories()
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
            yield return directory.Trim('"');
        foreach (var root in new[] { Environment.GetEnvironmentVariable("APPDATA"), Environment.GetEnvironmentVariable("LOCALAPPDATA") })
            if (!string.IsNullOrWhiteSpace(root)) yield return Path.Combine(root, "npm");
    }

    public static ProcessStartInfo StartInfo(string executable) => new()
    {
        FileName = executable,
        RedirectStandardOutput = true,
        RedirectStandardError = true,
        StandardOutputEncoding = System.Text.Encoding.UTF8,
        StandardErrorEncoding = System.Text.Encoding.UTF8,
        UseShellExecute = false,
        CreateNoWindow = true
    };
}
