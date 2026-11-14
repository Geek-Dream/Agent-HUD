using System.Diagnostics;
using AgentHUD.Core;
using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

public sealed class CodexInputAdapter : IAgentInputAdapter
{
    private static readonly TimeSpan DeliveryTimeout = TimeSpan.FromSeconds(15);
    private static readonly string[] VendorPackages =
    {
        "codex-win32-x64",
        "codex-win32-arm64"
    };

    public AgentProvider Provider => AgentProvider.Codex;

    public InputCapability CanAcceptInput(AgentSession session)
    {
        if (!session.IsLive)
        {
            return new InputCapability(false, InputState.Offline, "会话或进程已经离线。");
        }

        if (session.Status is not (AgentStatus.Working
            or AgentStatus.WaitingUser
            or AgentStatus.Idle
            or AgentStatus.Starting))
        {
            return new InputCapability(false, InputState.Busy, "当前状态不接受新输入。");
        }

        if (session.Status == AgentStatus.WaitingUser)
        {
            return new InputCapability(
                true,
                InputState.WaitingUser,
                "Agent 正在等待确认，发送内容将作为当前问题的回复。");
        }

        return new InputCapability(true, InputState.Ready, null);
    }

    public async Task<DeliveryResult> DeliverAsync(string text, AgentSession session)
    {
        var capability = CanAcceptInput(session);
        if (!capability.Enabled)
        {
            var error = capability.State == InputState.Offline
                ? DeliveryError.SessionOffline
                : DeliveryError.AgentBusy;
            return new DeliveryResult(false, DeliveryStatus.Failed, error);
        }

        var executable = FindCodexExecutable();
        if (executable is null)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.InputUnavailable);
        }

        // `codex queue` 对已经退出的会话同样返回成功，消息会被静默丢弃；
        // 所以先确认仍有进程持有该会话的 rollout 文件。
        if (!IsSessionAttached(session))
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.SessionOffline);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = executable,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        // 用 ArgumentList 传参，文本里的引号和空格不会被 shell 解释。
        startInfo.ArgumentList.Add("queue");
        startInfo.ArgumentList.Add("--thread");
        startInfo.ArgumentList.Add(session.ProviderSessionId);
        startInfo.ArgumentList.Add("--message");
        startInfo.ArgumentList.Add(text);

        try
        {
            using var process = new Process { StartInfo = startInfo };
            process.Start();
            var standardOutput = process.StandardOutput.ReadToEndAsync();
            var standardError = process.StandardError.ReadToEndAsync();

            using var timeout = new CancellationTokenSource(DeliveryTimeout);
            try
            {
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                TryKill(process);
                return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.DeliveryFailed);
            }

            var errorText = await standardError;
            _ = await standardOutput;

            if (process.ExitCode == 0)
            {
                return new DeliveryResult(true, DeliveryStatus.Delivered, null);
            }

            var error = errorText.Contains("no rollout found", StringComparison.OrdinalIgnoreCase)
                ? DeliveryError.SessionOffline
                : DeliveryError.DeliveryFailed;
            return new DeliveryResult(false, DeliveryStatus.Failed, error);
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.InputUnavailable);
        }
        catch (InvalidOperationException)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.DeliveryFailed);
        }
    }

    private static void TryKill(Process process)
    {
        try
        {
            process.Kill(entireProcessTree: true);
        }
        catch (InvalidOperationException)
        {
            return;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            return;
        }
    }

    private static bool IsSessionAttached(AgentSession session)
    {
        var path = session.SourcePath;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return session.IsLive;
        }

        try
        {
            // Codex 以写入方式持有 rollout 文件；独占打开成功说明已经没有进程在看它。
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None);
            return false;
        }
        catch (IOException)
        {
            return true;
        }
        catch (UnauthorizedAccessException)
        {
            return true;
        }
    }

    private static string? FindCodexExecutable()
    {
        foreach (var directory in SearchDirectories())
        {
            var direct = Path.Combine(directory, "codex.exe");
            if (File.Exists(direct))
            {
                return direct;
            }
        }

        // npm 安装的 codex 只有 codex.cmd 启动器，直接执行必须经过 cmd.exe；
        // 这里回溯到 node_modules 里的原生 codex.exe，避免拼 shell 字符串。
        foreach (var directory in SearchDirectories())
        {
            var openAiDirectory = Path.Combine(
                directory, "node_modules", "@openai", "codex", "node_modules", "@openai");
            if (!Directory.Exists(openAiDirectory))
            {
                continue;
            }

            foreach (var package in VendorPackages)
            {
                var vendorDirectory = Path.Combine(openAiDirectory, package, "vendor");
                if (!Directory.Exists(vendorDirectory))
                {
                    continue;
                }

                foreach (var tripleDirectory in Directory.EnumerateDirectories(vendorDirectory))
                {
                    var candidate = Path.Combine(tripleDirectory, "bin", "codex.exe");
                    if (File.Exists(candidate))
                    {
                        return candidate;
                    }
                }
            }
        }

        return null;
    }

    private static IEnumerable<string> SearchDirectories()
    {
        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            yield return directory.Trim('"');
        }

        foreach (var root in new[]
                 {
                     Environment.GetEnvironmentVariable("APPDATA"),
                     Environment.GetEnvironmentVariable("LOCALAPPDATA")
                 })
        {
            if (!string.IsNullOrWhiteSpace(root))
            {
                yield return Path.Combine(root, "npm");
            }
        }
    }
}
