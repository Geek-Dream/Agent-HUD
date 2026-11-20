using System.Diagnostics;
using AgentHUD.Core;
using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

/// <summary>通过 OpenCode 自带的后台服务向指定 session 投递文本，不依赖会话窗口仍打开。</summary>
public sealed class OpenCodeInputAdapter : IAgentInputAdapter
{
    private static readonly TimeSpan DeliveryTimeout = TimeSpan.FromSeconds(20);
    public AgentProvider Provider => AgentProvider.OpenCode;

    public InputCapability CanAcceptInput(AgentSession session)
    {
        if (string.IsNullOrWhiteSpace(session.ProviderSessionId))
        {
            return new InputCapability(false, InputState.Unavailable, "找不到 OpenCode 会话编号。");
        }
        if (session.Status == AgentStatus.WaitingUser)
        {
            return new InputCapability(true, InputState.WaitingUser, "Agent 正在等待确认，发送内容将作为当前问题的回复。");
        }
        if (session.Status == AgentStatus.Failed)
        {
            return new InputCapability(false, InputState.Busy, "会话已出错，请先在 OpenCode 中恢复后再发送。");
        }
        return new InputCapability(true, InputState.Ready,
            session.IsLive ? null : "将作为新指令继续这个已完成的 OpenCode 会话。");
    }

    public async Task<DeliveryResult> DeliverAsync(string text, AgentSession session)
    {
        var capability = CanAcceptInput(session);
        if (!capability.Enabled)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.InputUnavailable);
        }
        var executable = AgentExecutableFinder.FindOpenCode();
        if (executable is null)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.InputUnavailable);
        }

        // opencode api 的 JSON 参数必须完整转义；使用 --data 让 CLI 直接读取，
        // 不经过 shell，因此中文、引号和换行都能原样到达。
        var startInfo = AgentExecutableFinder.StartInfo(executable);
        foreach (var argument in new[]
                 {
                     "api", "session.prompt", "--param", $"sessionID={session.ProviderSessionId}",
                     "--data", $"{{\"text\":{System.Text.Json.JsonSerializer.Serialize(text)}}}"
                 })
        {
            startInfo.ArgumentList.Add(argument);
        }
        startInfo.Environment["HTTP_PROXY"] = string.Empty;
        startInfo.Environment["HTTPS_PROXY"] = string.Empty;
        startInfo.Environment["ALL_PROXY"] = string.Empty;

        try
        {
            using var process = new Process { StartInfo = startInfo };
            process.Start();
            var output = process.StandardOutput.ReadToEndAsync();
            var error = process.StandardError.ReadToEndAsync();
            using var timeout = new CancellationTokenSource(DeliveryTimeout);
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
            if (process.ExitCode == 0 && stdout.Contains("\"sessionID\"", StringComparison.Ordinal))
            {
                return new DeliveryResult(true, DeliveryStatus.Delivered, null);
            }
            var failureText = $"{stdout}\n{stderr}";
            return new DeliveryResult(false, DeliveryStatus.Failed,
                failureText.Contains("not found", StringComparison.OrdinalIgnoreCase)
                    ? DeliveryError.SessionOffline
                    : DeliveryError.DeliveryFailed);
        }
        catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.InputUnavailable);
        }
    }
}
