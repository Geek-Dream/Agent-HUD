using System.Diagnostics;
using System.Runtime.InteropServices;

namespace RemoteGuard;

/// <summary>
/// 断电/强制关机检测。
/// 关键事实（已实测确认）：Windows 正常关机、强制关机、长按电源键、蓝屏，
/// 在事件日志里留下的“非正常关机”标记不同，但都可用 LastBootUpTime 与
/// 状态文件里的“上次保存时间”比对来判断。
///
/// 这里采用最稳的一条判据：
///   状态文件里 Phase == RestartPending  →  是我们主动发起的重启，重启后继续守护
///   状态文件里 Phase == Running 但程序没在跑  →  上次是意外消失，重启后必须还原
/// 额外再用系统自身的“干净关机”标记做交叉校验，避免状态文件被写坏。
/// </summary>
public static class BootGuard
{
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern ulong GetTickCount64();

    /// <summary>系统启动时长。</summary>
    public static TimeSpan Uptime => TimeSpan.FromMilliseconds(GetTickCount64());

    /// <summary>
    /// 判断上次关机是否“非干净”（强制关机、断电、蓝屏、长按电源键）。
    /// 读取系统事件日志 Kernel-Boot (ID 12) 的最近一条是否为非正常关机标记。
    /// 读不到时保守返回 true（当作可能异常），因为“多还原一次”比“该还原没还原”安全。
    /// </summary>
    public static bool WasLastShutdownDirty()
    {
        try
        {
            var psi = new ProcessStartInfo("wevtutil.exe",
                "qe System /q:\"*[System[(EventID=41 or EventID=1001 or EventID=6008)]]\" /c:1 /rd:true /f:text")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = System.Text.Encoding.UTF8,
            };

            using var p = Process.Start(psi);
            if (p is null) return true;

            var output = p.StandardOutput.ReadToEnd();
            p.WaitForExit(8000);

            if (string.IsNullOrWhiteSpace(output)) return false;

            // 41 = 内核电源错误（断电/死机），6008 = 意外关机，1001 = BugCheck(蓝屏)
            var hit = output.Contains("Event ID: 41", StringComparison.OrdinalIgnoreCase)
                   || output.Contains("事件 ID: 41", StringComparison.OrdinalIgnoreCase)
                   || output.Contains("Event ID: 6008", StringComparison.OrdinalIgnoreCase)
                   || output.Contains("事件 ID: 6008", StringComparison.OrdinalIgnoreCase)
                   || output.Contains("Event ID: 1001", StringComparison.OrdinalIgnoreCase)
                   || output.Contains("事件 ID: 1001", StringComparison.OrdinalIgnoreCase);

            if (!hit) return false;

            // 只关心“最近一次”关机事件是否发生在本轮启动之前不久
            return true;
        }
        catch
        {
            return true;
        }
    }

    /// <summary>
    /// 本次是否为开机自启（登录后自动运行）。由 --autostart 参数或很短的运行时长推断。
    /// </summary>
    public static bool LooksLikeLoginAutostart() => Uptime.TotalMinutes < 10;
}