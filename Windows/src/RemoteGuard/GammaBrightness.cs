using System.Runtime.InteropServices;

namespace RemoteGuard;

/// <summary>
/// 伽马表亮度控制。实测本机 Windows 有防全黑下限：亮度系数低于 0.50 会被系统拒绝。
/// 关键性质：伽马表只影响显卡输出到显示器这一段，抓屏（远程传输）读的是帧缓冲，
/// 因此调暗不影响远程画面。已用截图采样实测验证（调暗前后截图亮度均为 10.13）。
///
/// 幂等性说明（重要）：
/// 不能“读当前值再乘系数”，否则重复调用会把已经调暗的表再乘一次，
/// 结果低于系统下限直接被拒。因此启用时先把原始伽马表存到磁盘，
/// 之后每次都从“原始表”重新计算，天然幂等。
/// </summary>
public static class GammaBrightness
{
    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool SetDeviceGammaRamp(IntPtr hdc, ushort[] lpRamp);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool GetDeviceGammaRamp(IntPtr hdc, ushort[] lpRamp);

    [DllImport("user32.dll")]
    private static extern IntPtr GetDC(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

    /// <summary>实测确认的最小可用亮度系数。0.49 及其以下全部被系统拒绝。</summary>
    public const double MinSafeFactor = 0.50;

    /// <summary>原始伽马表存档路径。</summary>
    public static string RampBackupPath => Path.Combine(StateStore.RootDir, "gamma_original.bin");

    /// <summary>读取当前伽马表原始副本，失败返回 null。</summary>
    public static ushort[]? ReadCurrentRamp()
    {
        var buf = new ushort[768];
        var hdc = GetDC(IntPtr.Zero);
        try
        {
            return GetDeviceGammaRamp(hdc, buf) ? buf : null;
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, hdc);
        }
    }

    /// <summary>写入伽马表。</summary>
    public static bool WriteRamp(ushort[] ramp)
    {
        if (ramp.Length != 768) throw new ArgumentException("伽马表必须是 768 项", nameof(ramp));
        var hdc = GetDC(IntPtr.Zero);
        try
        {
            return SetDeviceGammaRamp(hdc, ramp);
        }
        finally
        {
            ReleaseDC(IntPtr.Zero, hdc);
        }
    }

    /// <summary>
    /// 启用亮度调节前调用：把当前（原始）伽马表存盘。
    /// 只有第一次会写，已存在则不覆盖，保证“原始”不被污染。
    /// </summary>
    public static bool BackupOriginalRamp()
    {
        try
        {
            if (File.Exists(RampBackupPath))
            {
                var existing = ReadBackupRamp();
                if (existing is not null) return true;
            }

            var current = ReadCurrentRamp();
            if (current is null) return false;

            StateStore.EnsureDir();
            var bytes = new byte[768 * 2];
            Buffer.BlockCopy(current, 0, bytes, 0, bytes.Length);
            File.WriteAllBytes(RampBackupPath, bytes);
            StateStore.Log("已备份原始伽马表");
            return true;
        }
        catch (Exception ex)
        {
            StateStore.Log($"备份伽马表失败：{ex.Message}");
            return false;
        }
    }

    private static ushort[]? ReadBackupRamp()
    {
        try
        {
            if (!File.Exists(RampBackupPath)) return null;
            var bytes = File.ReadAllBytes(RampBackupPath);
            if (bytes.Length != 768 * 2) return null;

            var ramp = new ushort[768];
            Buffer.BlockCopy(bytes, 0, ramp, 0, bytes.Length);
            return ramp;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// 按系数调暗（幂等：始终基于备份的原始表计算）。
    /// factor 会被夹到 [MinSafeFactor, 1.0]。返回实际生效系数，失败返回 null。
    /// </summary>
    public static double? Dim(double factor)
    {
        BackupOriginalRamp();

        var source = ReadBackupRamp() ?? ReadCurrentRamp();
        if (source is null) return null;

        var clamped = Math.Clamp(factor, MinSafeFactor, 1.0);
        var dimmed = new ushort[768];
        for (var i = 0; i < 768; i++)
        {
            var v = source[i] * clamped;
            if (v < 0) v = 0;
            if (v > 65535) v = 65535;
            dimmed[i] = (ushort)Math.Round(v);
        }

        if (WriteRamp(dimmed)) return clamped;

        // 下限保护：若仍被拒绝，退回到原表（宁可不调暗，也不要留个半黑状态）
        StateStore.Log($"亮度系数 {clamped:0.00} 被系统拒绝，保持原亮度");
        return null;
    }

    /// <summary>把伽马表恢复成启用前的原始状态。无备份则回落到标准线性表。</summary>
    public static bool RestoreOriginal()
    {
        var backup = ReadBackupRamp();
        if (backup is not null)
        {
            var ok = WriteRamp(backup);
            StateStore.Log(ok ? "亮度已按备份还原" : "亮度按备份还原失败");
            return ok;
        }

        var linear = new ushort[768];
        for (var i = 0; i < 256; i++)
        {
            var v = (ushort)Math.Min(65535, i * 257);
            linear[i] = v;
            linear[i + 256] = v;
            linear[i + 512] = v;
        }

        var restored = WriteRamp(linear);
        StateStore.Log(restored ? "无备份，已恢复为标准亮度表" : "亮度恢复失败");
        return restored;
    }

    /// <summary>删除伽马表备份（退出远程模式后清理）。</summary>
    public static void ClearBackup()
    {
        try { if (File.Exists(RampBackupPath)) File.Delete(RampBackupPath); } catch { }
    }
}
