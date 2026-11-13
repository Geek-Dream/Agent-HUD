using System.Diagnostics;
using System.Runtime.InteropServices;
using AgentHUD.Core;
using AgentHUD.Link;

namespace AgentHUD.Windows.Services;

public sealed class CodexInputAdapter : IAgentInputAdapter
{
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

        try
        {
            await Task.Run(() => SendKeysToTerminal(text));
            return new DeliveryResult(true, DeliveryStatus.Delivered, null);
        }
        catch
        {
            return new DeliveryResult(false, DeliveryStatus.Failed, DeliveryError.DeliveryFailed);
        }
    }

    private static void SendKeysToTerminal(string text)
    {
        var escaped = text.Replace("{", "{{").Replace("}", "}}");
        var psi = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"$wshell = New-Object -ComObject wscript.shell; $wshell.SendKeys('{escaped}\"); $wshell.SendKeys('~')\"",
            CreateNoWindow = true,
            UseShellExecute = false
        };
        using var process = Process.Start(psi);
        process?.WaitForExit(TimeSpan.FromSeconds(5));
    }
}
