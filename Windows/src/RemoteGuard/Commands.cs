using System.Diagnostics;

namespace RemoteGuard;

/// <summary>
/// 各子命令实现。
///
/// 进程模型（关键设计）：
///   BAT → RemoteGuard.exe --start      （前台，秒退，输出写结果文件给 BAT 显示）
///            └─ 派生 RemoteGuard.exe --daemon   （后台常驻，无窗口）
///   BAT → RemoteGuard.exe --stop       （前台，秒退；先通知 daemon 退出再还原）
/// </summary>
public static class Commands
{
    /// <summary>守护进程检查状态的路径（通过 state.json 的 Phase 做跨进程通信）。</summary>
    private static GuardState LoadState() => StateStore.Load();

    // ================= 开启 =================

    public static int Start(Output output)
    {
        var state = LoadState();

        if (state.Phase == GuardPhase.Running && IsProcessAlive(state.GuardPid))
        {
            output.Write("远程办公模式已经在运行了，无需重复开启。");
            output.WriteBlank();
            output.Write("如需关闭，请双击后选择 [2]。");
            return 0;
        }

        // 首次开启采集基线；重复开启不覆盖，避免把远程模式当成“原样”存下来
        // 注意：必须判断 IsEmpty，因为历史版本可能留下空的 Baseline（已实测踩坑）
        if (state.Baseline is null || state.Baseline.IsEmpty)
        {
            state.Baseline = PowerPlan.Capture();
            StateStore.Log($"采集基线：{state.Baseline.Values.Count} 项，方案 {state.Baseline.ActiveSchemeGuid}");

            if (state.Baseline.IsEmpty)
            {
                output.Write("错误：无法读取当前电源设置，基线采集失败。");
                output.Write("为安全起见，不开启远程模式（避免无法还原）。");
                output.Write("请以管理员身份运行，或在命令行执行 powercfg /getactivescheme 检查。");
                state.Phase = GuardPhase.Idle;
                StateStore.Save(state);
                return 1;
            }
        }

        state.Phase = GuardPhase.Running;
        state.GuardPid = 0;
        StateStore.Save(state);

        // 派生后台守护进程
        var daemon = Program.SpawnSelf("--daemon");
        if (daemon is null)
        {
            // 派生失败就退回到在本进程里跑（BAT 会挂住，但至少功能可用）
            StateStore.Log("派生守护进程失败，改为前台运行");
            output.Write("警告：后台守护启动失败，转前台运行。关闭此窗口会停止守护。");
            return RunDaemonLoop(output);
        }

        // 等守护进程把 PID 写进 state.json
        var pid = WaitForPid(5000);

        output.Write("================ 已开启远程办公模式 ================");
        output.WriteBlank();
        output.Write("  电源 : 永不睡眠、永不休眠、不关硬盘");
        output.Write("  熄屏 : 5 分钟后关闭本地显示器（远程画面不受影响）");
        output.Write("  亮度 : 调至最低可用值（约 50%，系统下限）");
        output.Write("  守护 : RustDesk 与 Tailscale 关闭后会自动拉起");
        output.WriteBlank();
        output.Write($"  守护进程 PID：{(pid > 0 ? pid.ToString() : "启动中")}");
        output.Write("  原电源设置已备份，取消时逐项还原");
        output.WriteBlank();
        output.Write("===================================================");
        return 0;
    }

    // ================= 关闭 =================

    public static int Stop(Output output)
    {
        var state = LoadState();

        var wasActive = state.Phase != GuardPhase.Idle;
        if (!wasActive && !IsAnyGuardAdjusted())
        {
            output.Write("当前没有处于远程办公模式。");
            output.WriteBlank();
            output.Write("如果你只是想确认状态，可以选 [3] 查看。");
        }

        // 让守护进程退出：把它认的 Phase 改成 Idle，它会自行收尾退出
        if (state.Phase == GuardPhase.Running && IsProcessAlive(state.GuardPid))
        {
            state.Phase = GuardPhase.Idle;
            StateStore.Save(state);
            WaitForExit(state.GuardPid, 8000);
            state = LoadState();
        }

        // 无论守护进程是否还在，前台都执行一次还原，保证幂等
        using (var engine = new GuardEngine())
        {
            engine.RestoreBaseline(state, stopGuardedApps: false);
        }

        AutoStart.Unregister();

        state.Phase = GuardPhase.Idle;
        state.GuardPid = 0;
        state.AutoStartRegistered = false;
        StateStore.Save(state);

        if (wasActive)
        {
            output.Write("================ 已退出远程办公模式 ================");
            output.WriteBlank();
            output.Write("  电源 : 已还原为开启前的设置");
            output.Write("  亮度 : 已还原为系统默认");
            output.Write("  守护 : 已停止，不再监控程序");
            output.WriteBlank();
            output.Write("  RustDesk 和 Tailscale 保持运行，未强制关闭");
            output.WriteBlank();
            output.Write("===================================================");
        }
        return 0;
    }

    // ================= 重启 =================

    public static int Restart(Output output)
    {
        var state = LoadState();

        if (state.Phase != GuardPhase.Running)
        {
            output.Write("当前没有开启远程办公模式。");
            output.WriteBlank();
            output.Write("“计划重启后继续保持”只在守护运行时有意义。");
            return 1;
        }

        state.Phase = GuardPhase.RestartPending;
        StateStore.Save(state);

        AutoStart.Register(AutoStart.CurrentExePath);
        state.AutoStartRegistered = true;
        StateStore.Save(state);

        StateStore.Log("已标记计划重启并注册开机自启");

        output.Write("================ 准备重启 ================");
        output.WriteBlank();
        output.Write("  重启后将自动恢复：");
        output.Write("    · 远程办公模式的电源设置");
        output.Write("    · 最低亮度");
        output.Write("    · RustDesk / Tailscale 守护");
        output.WriteBlank();
        output.Write("  5 秒后开始重启…");
        output.Write("==========================================");

        Thread.Sleep(5000);

        try
        {
            Process.Start(new ProcessStartInfo("shutdown.exe", "/r /t 0")
            {
                CreateNoWindow = true,
                UseShellExecute = false,
            });
        }
        catch (Exception ex)
        {
            output.Write($"重启命令执行失败：{ex.Message}");
            return 1;
        }
        return 0;
    }

    // ================= 开机自启入口 =================

    /// <summary>
    /// 开机自启只做一件事：读状态文件，决定“继续守护”还是“还原原样”。
    /// 这是“强制关机后必须100%恢复原样”的兜底。
    /// </summary>
    public static int AutoStartEntry(Output output)
    {
        var state = LoadState();

        switch (state.Phase)
        {
            case GuardPhase.RestartPending:
                // 我们主动发起的重启 → 继续远程模式
                StateStore.Log("自启：检测到计划重启，继续远程办公模式");
                state.Phase = GuardPhase.Running;
                state.GuardPid = 0;
                StateStore.Save(state);
                Program.SpawnSelf("--daemon");
                return 0;

            case GuardPhase.Running:
                // 守护没跑却留下 Running 状态 → 上次是意外消失，必须还原
                StateStore.Log("自启：检测到上次意外退出，执行还原");
                using (var engine = new GuardEngine())
                {
                    engine.RestoreBaseline(state, stopGuardedApps: false);
                }
                AutoStart.Unregister();
                state.Phase = GuardPhase.Idle;
                state.GuardPid = 0;
                state.AutoStartRegistered = false;
                StateStore.Save(state);
                return 0;

            default:
                StateStore.Log("自启：无待处理状态，清理自启项");
                AutoStart.Unregister();
                return 0;
        }
    }

    // ================= 后台守护进程 =================

    public static int Daemon(Output output)
    {
        var state = LoadState();
        if (state.Phase != GuardPhase.Running)
        {
            StateStore.Log("守护进程启动时相位不是 Running，直接退出");
            return 0;
        }

        // 抢占单实例
        using var mutex = new Mutex(false, StateStore.MutexName, out var createdNew);
        if (!createdNew)
        {
            StateStore.Log("已有守护进程在运行，本实例退出");
            return 0;
        }

        state.GuardPid = Environment.ProcessId;
        StateStore.Save(state);
        StateStore.Log($"守护进程启动 PID={Environment.ProcessId}");

        using var engine = new GuardEngine();
        engine.ApplyRemoteEnvironment();
        engine.Start();

        // 主循环：随时看状态文件，被要求退出就收尾
        var stopFileWatch = new ManualResetEventSlim(false);
        while (!stopFileWatch.Wait(1000))
        {
            if (LoadState().Phase != GuardPhase.Running)
                break;
        }

        engine.Stop();
        StateStore.Log("守护进程收到退出信号，正在恢复原样");

        // 守护进程自己退出时也要还原，这是第 1 层兜底
        var latest = LoadState();
        engine.RestoreBaseline(latest, stopGuardedApps: false);

        latest.Phase = GuardPhase.Idle;
        latest.GuardPid = 0;
        StateStore.Save(latest);
        StateStore.Log("守护进程已退出");
        return 0;
    }

    /// <summary>独立还原后退出（供外部强制调用）。</summary>
    public static int RestoreAndExit(Output output)
    {
        var state = LoadState();
        using var engine = new GuardEngine();
        engine.RestoreBaseline(state, stopGuardedApps: false);

        state.Phase = GuardPhase.Idle;
        state.GuardPid = 0;
        StateStore.Save(state);
        output.Write("已恢复原样。");
        return 0;
    }

    // ================= 状态 =================

    public static int Status(Output output)
    {
        var state = LoadState();
        var scheme = PowerPlan.GetActiveSchemeGuid();
        var alive = IsProcessAlive(state.GuardPid);

        output.Write("================== 当前状态 ==================");
        output.Write($"  模式     : {Describe(state.Phase)}");
        output.Write($"  守护进程 : {(alive ? $"运行中 (PID {state.GuardPid})" : "未运行")}");
        output.Write($"  电源方案 : {scheme}");
        output.Write($"  自启项   : {(AutoStart.IsRegistered() ? "已注册" : "未注册")}");
        output.WriteBlank();

        if (state.Baseline is { IsEmpty: false } b)
        {
            output.Write("  开机前备份（原样）：");
            foreach (var (_, set, name, toggle) in PowerPlan.Tracked)
            {
                if (b.Values.TryGetValue(set, out var v))
                    output.Write($"    {name}: 交流 {PowerPlan.DescribeValue(v.Ac, toggle)} / 电池 {PowerPlan.DescribeValue(v.Dc, toggle)}");
            }
        }
        else
        {
            output.Write("  开机前备份（原样）：无（说明从未开启过）");
        }

        output.WriteBlank();
        if (scheme is not null)
        {
            output.Write("  当前实际设置：");
            foreach (var (sub, set, name, toggle) in PowerPlan.Tracked)
            {
                var v = PowerPlan.GetSetting(scheme, sub, set);
                if (v is not null)
                    output.Write($"    {name}: 交流 {PowerPlan.DescribeValue(v.Ac, toggle)} / 电池 {PowerPlan.DescribeValue(v.Dc, toggle)}");
            }
        }

        output.WriteBlank();
        output.Write("  远程程序：");
        output.Write($"    RustDesk  服务{(GuardedApps.IsServiceRunning(GuardedApps.RustDeskService) ? "在跑" : "停着")}，" +
                     $"程序{(GuardedApps.IsProcessRunning(GuardedApps.RustDeskExe) ? "在跑" : "停着")}");
        output.Write($"    Tailscale 服务{(GuardedApps.IsServiceRunning(GuardedApps.TailscaleService) ? "在跑" : "停着")}，" +
                     $"程序{(GuardedApps.IsProcessRunning(GuardedApps.TailscaleExe) ? "在跑" : "停着")}");
        output.Write("=============================================");
        return 0;
    }

    public static int Help(Output output)
    {
        output.Write("远程办公守护 - 命令行用法");
        output.WriteBlank();
        output.Write("  --start      开启远程办公模式");
        output.Write("  --stop       取消并恢复原样");
        output.Write("  --restart    计划重启（重启后继续保持）");
        output.Write("  --status     查看当前状态");
        output.Write("  --mode       仅输出机器可读状态（ASCII）");
        output.Write("  --out=文件   把输出写入指定文件");
        return 0;
    }

    /// <summary>
    /// 只输出一行 ASCII 状态，供 BAT 判断，避免批处理去解析中文。
    /// 输出：RUNNING / RESTART_PENDING / IDLE，并附带守护进程是否真的活着。
    /// </summary>
    public static int ModeOnly(Output output)
    {
        var state = LoadState();
        var alive = IsProcessAlive(state.GuardPid);

        var mode = state.Phase switch
        {
            GuardPhase.Running => "RUNNING",
            GuardPhase.RestartPending => "RESTART_PENDING",
            _ => "IDLE",
        };

        output.Write($"MODE={mode}");
        output.Write($"DAEMON_PID={state.GuardPid}");
        output.Write($"DAEMON_ALIVE={(alive ? 1 : 0)}");
        output.Write($"AUTOSTART={(AutoStart.IsRegistered() ? 1 : 0)}");
        output.Write($"BASELINE_ITEMS={(state.Baseline?.Values.Count ?? 0)}");
        output.Write($"RUSTDESK_SERVICE={(GuardedApps.IsServiceRunning(GuardedApps.RustDeskService) ? 1 : 0)}");
        output.Write($"RUSTDESK_APP={(GuardedApps.IsProcessRunning(GuardedApps.RustDeskExe) ? 1 : 0)}");
        output.Write($"TAILSCALE_SERVICE={(GuardedApps.IsServiceRunning(GuardedApps.TailscaleService) ? 1 : 0)}");
        output.Write($"TAILSCALE_APP={(GuardedApps.IsProcessRunning(GuardedApps.TailscaleExe) ? 1 : 0)}");
        return 0;
    }

    // ================= 内部工具 =================

    private static int RunDaemonLoop(Output output)
    {
        var state = LoadState();
        using var engine = new GuardEngine();
        engine.ApplyRemoteEnvironment();
        engine.Start();

        var stop = new ManualResetEventSlim(false);
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; stop.Set(); };
        stop.Wait();

        engine.Stop();
        engine.RestoreBaseline(state, stopGuardedApps: false);
        return 0;
    }

    private static bool IsAnyGuardAdjusted()
    {
        var state = LoadState();
        return state.Phase != GuardPhase.Idle || AutoStart.IsRegistered();
    }

    private static int WaitForPid(int timeoutMs)
    {
        var deadline = DateTime.UtcNow.AddMilliseconds(timeoutMs);
        while (DateTime.UtcNow < deadline)
        {
            var s = LoadState();
            if (s.GuardPid > 0 && IsProcessAlive(s.GuardPid)) return s.GuardPid;
            Thread.Sleep(100);
        }
        return 0;
    }

    private static string Describe(GuardPhase phase) => phase switch
    {
        GuardPhase.Running => "[ 远程办公模式 已开启 ]",
        GuardPhase.RestartPending => "[ 已安排重启，重启后自动恢复 ]",
        _ => "[ 未开启（原样状态） ]",
    };

    private static string Fmt(uint seconds)
    {
        if (seconds == 0) return "从不";
        if (seconds % 3600 == 0) return $"{seconds / 3600} 小时";
        if (seconds % 60 == 0) return $"{seconds / 60} 分钟";
        return $"{seconds} 秒";
    }

    private static bool IsProcessAlive(int pid)
    {
        if (pid <= 0) return false;
        if (pid == Environment.ProcessId) return true;
        try
        {
            using var p = Process.GetProcessById(pid);
            return !p.HasExited;
        }
        catch { return false; }
    }

    private static void WaitForExit(int pid, int timeoutMs)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            p.WaitForExit(timeoutMs);
        }
        catch { }
    }
}