using System.Diagnostics;
using AgentHUD.Core;
using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

public sealed class ClaudeInputAdapter : IAgentInputAdapter
{
    private static readonly TimeSpan StartTimeout = TimeSpan.FromSeconds(20);
    public AgentProvider Provider => AgentProvider.Claude;

    public InputCapability CanAcceptInput(AgentSession session)
    {
        if (string.IsNullOrWhiteSpace(session.ProviderSessionId))
        {
            return new InputCapability(false, InputState.Unavailable, "找不到 Claude 会话编号。");
        }
        if (session.IsLive)
        {
            // `claude --bg --resume` 对正在运行的会话会另开副本，不能冒充
            // 已向原会话投递；等本轮结束后再续聊才是确定行为。
            return new InputCapability(false, InputState.Busy,
                "Claude 正在处理当前轮次，请完成后再发送续聊指令。");
        }
        return new InputCapability(true, InputState.Ready,
            "将后台恢复这个 Claude 会话并发送新指令。");
    }

    public async Task<DeliveryResult> DeliverAsync(string text, AgentSession session)
    {
        var capability = CanAcceptInput(session);
        if (!capability.Enabled)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.AgentBusy);
        }
        var executable = AgentExecutableFinder.FindClaude();
        if (executable is null)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.InputUnavailable);
        }

        var startInfo = AgentExecutableFinder.StartInfo(executable);
        foreach (var argument in new[] { "--bg", "--resume", session.ProviderSessionId, text })
        {
            startInfo.ArgumentList.Add(argument);
        }
        if (Directory.Exists(session.ProjectPath))
        {
            startInfo.WorkingDirectory = session.ProjectPath;
        }

        try
        {
            using var process = new Process { StartInfo = startInfo };
            process.Start();
            var output = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            using var timeout = new CancellationTokenSource(StartTimeout);
            try
            {
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                try { process.Kill(entireProcessTree: true); } catch { }
                return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.DeliveryFailed);
            }
            var stdout = await output;
            var stderr = await error;
            if (process.ExitCode == 0 && !string.IsNullOrWhiteSpace(stdout))
            {
                // --bg 只保证后台启动器接管；结束手机端轮询，但不能宣称
                // 已经观察到 Agent 执行（Observed）。
                return new DeliveryResult(true, DeliveryStatus.Delivered, null);
            }
            return new DeliveryResult(false, DeliveryStatus.Failed,
                stderr.Contains("No conversation found", StringComparison.OrdinalIgnoreCase)
                    ? DeliveryError.SessionOffline
                    : DeliveryError.DeliveryFailed);
        }
        catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.InputUnavailable);
        }
    }
}
