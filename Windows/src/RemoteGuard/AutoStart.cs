using System.Diagnostics;

namespace RemoteGuard;

/// <summary>开机自启：写 HKCU 的 Run 项，不需要管理员权限，取消时精确删除。</summary>
public static class AutoStart
{
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "RemoteGuard";

    public static bool IsRegistered()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey);
            var v = key?.GetValue(ValueName) as string;
            return !string.IsNullOrWhiteSpace(v);
        }
        catch { return false; }
    }

    /// <summary>注册自启。登录后以“恢复”模式启动，恢复远程模式和亮度。</summary>
    public static bool Register(string exePath)
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RunKey);
            if (key is null) return false;
            key.SetValue(ValueName, $"\"{exePath}\" --autostart", Microsoft.Win32.RegistryValueKind.String);
            return true;
        }
        catch { return false; }
    }

    public static bool Unregister()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RunKey, writable: true);
            if (key?.GetValue(ValueName) is not null)
                key.DeleteValue(ValueName, throwOnMissingValue: false);
            return true;
        }
        catch { return false; }
    }

    /// <summary>当前可执行文件路径（发布后为 RemoteGuard.exe）。</summary>
    public static string CurrentExePath
    {
        get
        {
            var p = Environment.ProcessPath;
            if (!string.IsNullOrWhiteSpace(p)) return p!;

            using var cur = Process.GetCurrentProcess();
            return cur.MainModule?.FileName ?? string.Empty;
        }
    }
}