using System.Diagnostics;

namespace RemoteGuard;

/// <summary>
/// 命令行入口。
///
/// 用法（由桌面 BAT 调用，也可手动跑）：
///   RemoteGuard.exe --start  --out=结果文件   开启守护（远程办公模式）
///   RemoteGuard.exe --stop   --out=结果文件   取消守护并恢复原样
///   RemoteGuard.exe --restart --out=结果文件  记录“计划重启”后重启电脑
///   RemoteGuard.exe --autostart               开机自启入口（判断继续还是还原）
///   RemoteGuard.exe --status --out=结果文件   打印当前状态
///
/// 内部子命令（由 --start 自行派生，不要手动调用）：
///   RemoteGuard.exe --daemon                  常驻守护进程
///   RemoteGuard.exe --restore-and-exit        还原设置后退出
/// </summary>
public static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var cmd = (args.Length > 0 && !args[0].StartsWith("--out=") ? args[0] : "--help")
            .Trim().ToLowerInvariant();

        var outFile = args
            .FirstOrDefault(a => a.StartsWith("--out=", StringComparison.OrdinalIgnoreCase))?
            .Substring("--out=".Length);

        var output = new Output(outFile);
        StateStore.EnsureDir();

        try
        {
            var code = cmd switch
            {
                "--start" => Commands.Start(output),
                "--stop" => Commands.Stop(output),
                "--restart" => Commands.Restart(output),
                "--autostart" => Commands.AutoStartEntry(output),
                "--status" => Commands.Status(output),
                "--mode" => Commands.ModeOnly(output),
                "--daemon" => Commands.Daemon(output),
                "--restore-and-exit" => Commands.RestoreAndExit(output),
                _ => Commands.Help(output),
            };
            return code;
        }
        catch (Exception ex)
        {
            StateStore.Log($"未处理异常（{cmd}）：{ex}");
            output.Write($"发生未处理异常：{ex.Message}");
            return 1;
        }
        finally
        {
            output.Flush();
        }
    }

    /// <summary>派生子进程（守护/还原）时的通用启动。</summary>
    internal static Process? SpawnSelf(string arg)
    {
        try
        {
            var psi = new ProcessStartInfo(AutoStart.CurrentExePath, arg)
            {
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                WorkingDirectory = AppContext.BaseDirectory,
            };
            return Process.Start(psi);
        }
        catch (Exception ex)
        {
            StateStore.Log($"派生子进程失败（{arg}）：{ex.Message}");
            return null;
        }
    }
}