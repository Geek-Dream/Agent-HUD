using System.Diagnostics;

namespace RemoteGuard;

/// <summary>
/// 守护核心：定时检查 RustDesk / Tailscale，缺失则拉起，卡死则先礼后兵。
/// 所有动作写日志，便于事后判断是否发生过恢复动作。
/// </summary>
public sealed class GuardEngine : IDisposable
{
    private readonly CancellationTokenSource _cts = new();
    private Thread? _thread;
    private volatile bool _running;

    /// <summary>检查间隔。</summary>
    public TimeSpan Interval { get; set; } = TimeSpan.FromSeconds(5);

    /// <summary>熄屏等待时长（远程模式下）。</summary>
    public TimeSpan ScreenOffAfter { get; set; } = TimeSpan.FromMinutes(5);

    /// <summary>亮度系数，实测下限 0.50。</summary>
    public double BrightnessFactor { get; set; } = GammaBrightness.MinSafeFactor;

    /// <summary>每次检查到异常时的回调（用于界面提示）。</summary>
    public event Action<string>? OnEvent;

    public bool IsRunning => _running;

    public void Start()
    {
        if (_running) return;
        _running = true;

        _thread = new Thread(Loop)
        {
            IsBackground = true,
            Name = "RemoteGuard.Worker",
        };
        _thread.Start();
    }

    public void Stop()
    {
        try { _cts.Cancel(); } catch { }
        _running = false;
    }

    private void Loop()
    {
        var token = _cts.Token;

        while (!token.IsCancellationRequested)
        {
            try
            {
                CheckOnce();
            }
            catch (Exception ex)
            {
                StateStore.Log($"检查异常：{ex.Message}");
                Raise($"检查异常：{ex.Message}");
            }

            // 分片等待，便于快速响应取消
            for (var i = 0; i < Interval.TotalMilliseconds / 200 && !token.IsCancellationRequested; i++)
                Thread.Sleep(200);
        }
    }

    /// <summary>防止同一进程内重复施加（电源与亮度都只做一次）。</summary>
    private int _applied;

    /// <summary>
    /// 置入远程办公环境：电源参数 + 亮度。
    /// 幂等：重复调用不会把亮度叠乘（伽马表始终基于备份原始表重算）。
    /// </summary>
    public void ApplyRemoteEnvironment()
    {
        if (Interlocked.Exchange(ref _applied, 1) == 1) return;

        try
        {
            PowerPlan.ApplyRemoteMode(ScreenOffAfter);
            StateStore.Log($"电源已切换：睡眠/休眠/硬盘=从不，熄屏={ScreenOffAfter.TotalMinutes}分钟");

            var applied = GammaBrightness.Dim(BrightnessFactor);
            if (applied is not null)
                StateStore.Log($"亮度已调至 {applied:0.00}（实测下限 0.50，远程画面不受影响）");
            else
                StateStore.Log("亮度调节失败（伽马表不可写），跳过");
        }
        catch (Exception ex)
        {
            StateStore.Log($"应用远程环境失败：{ex.Message}");
        }
    }

    /// <summary>单次巡检。</summary>
    private void CheckOnce()
    {
        EnsureRustDesk();
        EnsureTailscale();
    }

    private void EnsureRustDesk()
    {
        // 1) 服务
        if (!GuardedApps.IsServiceRunning(GuardedApps.RustDeskService))
        {
            StateStore.Log("RustDesk 服务未运行，正在启动…");
            if (GuardedApps.EnsureService(GuardedApps.RustDeskService))
            {
                StateStore.Log("RustDesk 服务已启动");
                Raise("RustDesk 服务已重新启动");
            }
            else
            {
                StateStore.Log("RustDesk 服务启动失败");
                Raise("RustDesk 服务启动失败");
            }
        }

        // 2) 用户态程序
        if (!GuardedApps.IsProcessRunning(GuardedApps.RustDeskExe))
        {
            StateStore.Log("RustDesk 程序不在运行，正在拉起…");
            if (GuardedApps.StartRustDesk())
            {
                StateStore.Log("RustDesk 程序已拉起");
                Raise("RustDesk 已重新启动");
            }
            else
            {
                StateStore.Log("RustDesk 拉起失败");
                Raise("RustDesk 拉起失败");
            }
        }
    }

    private void EnsureTailscale()
    {
        if (!GuardedApps.IsServiceRunning(GuardedApps.TailscaleService))
        {
            StateStore.Log("Tailscale 服务未运行，正在启动…");
            if (GuardedApps.EnsureService(GuardedApps.TailscaleService))
            {
                StateStore.Log("Tailscale 服务已启动");
                Raise("Tailscale 服务已重新启动");
            }
            else
            {
                StateStore.Log("Tailscale 服务启动失败");
                Raise("Tailscale 服务启动失败");
            }
        }

        if (!GuardedApps.IsProcessRunning(GuardedApps.TailscaleExe))
        {
            StateStore.Log("Tailscale 托盘程序不在运行，正在拉起…");
            if (GuardedApps.StartTailscale())
            {
                StateStore.Log("Tailscale 托盘程序已拉起");
                Raise("Tailscale 已重新启动");
            }
            else
            {
                StateStore.Log("Tailscale 拉起失败");
                Raise("Tailscale 拉起失败");
            }
        }
    }

    /// <summary>
    /// 结束守护并恢复原样：电源快照写回、亮度复原、可选结束被守护程序。
    /// </summary>
    public bool RestoreBaseline(GuardState state, bool stopGuardedApps)
    {
        var ok = true;

        try
        {
            if (state.Baseline is { IsEmpty: false })
            {
                ok &= PowerPlan.Apply(state.Baseline);
                StateStore.Log($"电源已还原为原方案快照（{state.Baseline.Values.Count} 项）");
            }
            else
            {
                StateStore.Log("没有可用快照，电源设置未改动（保持系统现值）");
            }
        }
        catch (Exception ex)
        {
            StateStore.Log($"还原电源失败：{ex.Message}");
            ok = false;
        }

        try
        {
            GammaBrightness.RestoreOriginal();
            StateStore.Log("亮度已复原为系统默认");
        }
        catch (Exception ex)
        {
            StateStore.Log($"还原亮度失败：{ex.Message}");
        }

        if (stopGuardedApps)
        {
            StateStore.Log("按要求结束远程程序…");
            GuardedApps.GracefulStop(GuardedApps.RustDeskExe);
            GuardedApps.GracefulStop(GuardedApps.TailscaleExe);
        }

        // 还原完成后清掉伽马表备份，避免下次开启时拿旧备份当“原始值”
        GammaBrightness.ClearBackup();

        return ok;
    }

    private void Raise(string message) => OnEvent?.Invoke(message);

    public void Dispose()
    {
        try { _cts.Cancel(); } catch { }
        try { _cts.Dispose(); } catch { }
    }
}