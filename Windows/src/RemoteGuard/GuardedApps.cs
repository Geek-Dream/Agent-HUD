using System.Diagnostics;
using System.ServiceProcess;

namespace RemoteGuard;

/// <summary>
/// 被守护的进程：RustDesk（远程桌面）和 Tailscale（局域网 VPN）。
/// 两者都是“服务 + 用户态托盘程序”的结构：
///   RustDesk : RustDesk.exe --service(服务) → --server(核心) ；另需主程序 + --tray(托盘)
///   Tailscale: tailscaled.exe(服务)        → tailscale-ipn.exe(托盘)
/// 守护以“服务在跑 + 托盘程序在跑”为健康判据，那才是能远程连进来的完整状态。
/// 刻意不引入 System.Management（.NET 8 需额外包），全部用进程/服务 API 与 sc.exe。
/// </summary>
public static class GuardedApps
{
    public const string RustDeskExe = @"E:\Program Files\RustDesk\RustDesk\rustdesk.exe";
    public const string RustDeskService = "RustDesk";

    public const string TailscaleExe = @"C:\Program Files\Tailscale\tailscale-ipn.exe";
    public const string TailscaleService = "Tailscale";

    /// <summary>按进程名判断是否在运行。</summary>
    public static bool IsProcessRunning(string exePathOrName)
    {
        var name = Path.GetFileNameWithoutExtension(exePathOrName);
        try
        {
            return Process.GetProcessesByName(name).Length > 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>服务是否 Running（用 sc query，避免 ServiceController 偶发超时）。</summary>
    public static bool IsServiceRunning(string serviceName)
    {
        var output = RunHidden("sc.exe", $"query \"{serviceName}\"");
        return output.Contains("RUNNING", StringComparison.OrdinalIgnoreCase)
            || output.Contains("运行", StringComparison.OrdinalIgnoreCase);
    }

    /// <summary>确保服务在运行，必要时启动。</summary>
    public static bool EnsureService(string serviceName, int timeoutMs = 20000)
    {
        if (IsServiceRunning(serviceName)) return true;

        RunHidden("sc.exe", $"start \"{serviceName}\"");

        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            if (IsServiceRunning(serviceName)) return true;
            Thread.Sleep(300);
        }
        return false;
    }

    /// <summary>RustDesk 完整可用：服务 + 用户态程序都在。</summary>
    public static bool RustDeskHealthy() =>
        IsServiceRunning(RustDeskService) && IsProcessRunning(RustDeskExe);

    /// <summary>Tailscale 完整可用：服务 + 托盘程序都在。</summary>
    public static bool TailscaleHealthy() =>
        IsServiceRunning(TailscaleService) && IsProcessRunning(TailscaleExe);

    /// <summary>启动 RustDesk 用户态程序。</summary>
    public static bool StartRustDesk() => StartDetached(RustDeskExe);

    /// <summary>启动 Tailscale 托盘程序。</summary>
    public static bool StartTailscale() => StartDetached(TailscaleExe);

    private static bool StartDetached(string exePath)
    {
        try
        {
            if (!File.Exists(exePath)) return false;
            Process.Start(new ProcessStartInfo(exePath)
            {
                UseShellExecute = true,
                WorkingDirectory = Path.GetDirectoryName(exePath)!
            });
            return true;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// 友好关闭：正常关闭信号最多尝试 maxAttempts 次，全部失败再强制结束。
    /// </summary>
    public static bool GracefulStop(string exePathOrName, int maxAttempts = 3, int timeoutMs = 3000)
    {
        var name = Path.GetFileNameWithoutExtension(exePathOrName);

        for (var attempt = 1; attempt <= maxAttempts; attempt++)
        {
            var procs = Process.GetProcessesByName(name);
            if (procs.Length == 0) return true;

            foreach (var p in procs)
            {
                try { p.CloseMainWindow(); } catch { }
                p.Dispose();
            }

            var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
            while (DateTime.UtcNow < deadline)
            {
                if (Process.GetProcessesByName(name).Length == 0) return true;
                Thread.Sleep(150);
            }
        }

        return ForceStop(exePathOrName);
    }

    /// <summary>强制结束该进程名下的所有进程树。</summary>
    public static bool ForceStop(string exePathOrName)
    {
        var name = Path.GetFileNameWithoutExtension(exePathOrName);
        RunHidden("taskkill.exe", $"/F /T /IM {name}.exe");

        try
        {
            foreach (var p in Process.GetProcessesByName(name))
            {
                try { p.Kill(entireProcessTree: true); } catch { }
                p.Dispose();
            }
        }
        catch { }

        Thread.Sleep(400);
        return Process.GetProcessesByName(name).Length == 0;
    }

    /// <summary>静默执行命令并返回标准输出。</summary>
    private static string RunHidden(string file, string args, int timeoutMs = 15000)
    {
        try
        {
            var psi = new ProcessStartInfo(file, args)
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
            };
            using var p = Process.Start(psi);
            if (p is null) return string.Empty;
            var text = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
            p.WaitForExit(timeoutMs);
            return text;
        }
        catch
        {
            return string.Empty;
        }
    }
}
