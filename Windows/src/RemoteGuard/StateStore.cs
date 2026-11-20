using System.Text.Json;
using System.Text.Json.Serialization;

namespace RemoteGuard;

/// <summary>守护运行状态。用于区分“计划重启”和“意外退出”。</summary>
public enum GuardPhase
{
    /// <summary>没有守护在跑，一切应为原样。</summary>
    Idle = 0,

    /// <summary>守护正在运行（正常值守中）。</summary>
    Running = 1,

    /// <summary>用户从菜单里选择了“重启电脑”，重启后应自动恢复远程模式。</summary>
    RestartPending = 2,
}

/// <summary>持久化状态文件内容。</summary>
public sealed class GuardState
{
    public GuardPhase Phase { get; set; } = GuardPhase.Idle;

    /// <summary>开启前采集的电源设置快照。</summary>
    public PowerPlan.Snapshot? Baseline { get; set; }

    /// <summary>记录的自启方式，便于取消时精确回滚。</summary>
    public bool AutoStartRegistered { get; set; }

    /// <summary>最近一次保存时间（UTC）。</summary>
    public DateTime UpdatedUtc { get; set; } = DateTime.UtcNow;

    /// <summary>守护进程 PID，用于防止重复启动。</summary>
    public int GuardPid { get; set; }

    /// <summary>写入状态文件的版本，便于将来迁移。</summary>
    public int Version { get; set; } = 1;

    [JsonIgnore]
    public bool IsActive => Phase != GuardPhase.Idle;
}

/// <summary>
/// 状态文件读写 + 跨进程互斥。
/// 位置：%LOCALAPPDATA%\RemoteGuard\state.json
/// 这是“意外退出后能否恢复原样”的唯一依据，因此写入一律先写临时文件再替换。
/// </summary>
public static class StateStore
{
    public static string RootDir { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "RemoteGuard");

    public static string StatePath => Path.Combine(RootDir, "state.json");
    public static string LogPath => Path.Combine(RootDir, "guard.log");
    public static string MutexName => @"Global\RemoteGuard.SingleInstance";

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        Converters = { new JsonStringEnumConverter() },
    };

    public static void EnsureDir()
    {
        try { Directory.CreateDirectory(RootDir); } catch { }
    }

    public static GuardState Load()
    {
        try
        {
            if (!File.Exists(StatePath)) return new GuardState();
            var json = File.ReadAllText(StatePath);
            if (string.IsNullOrWhiteSpace(json)) return new GuardState();
            return JsonSerializer.Deserialize<GuardState>(json, JsonOpts) ?? new GuardState();
        }
        catch
        {
            return new GuardState();
        }
    }

    public static bool Save(GuardState state)
    {
        try
        {
            EnsureDir();
            state.UpdatedUtc = DateTime.UtcNow;
            var json = JsonSerializer.Serialize(state, JsonOpts);

            var tmp = StatePath + ".tmp";
            File.WriteAllText(tmp, json);

            if (File.Exists(StatePath))
            {
                try { File.Replace(tmp, StatePath, null); }
                catch { File.Copy(tmp, StatePath, overwrite: true); File.Delete(tmp); }
            }
            else
            {
                File.Move(tmp, StatePath);
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    public static void Clear()
    {
        try { if (File.Exists(StatePath)) File.Delete(StatePath); } catch { }
    }

    public static void Log(string message)
    {
        try
        {
            EnsureDir();
            var line = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {message}{Environment.NewLine}";
            File.AppendAllText(LogPath, line);

            // 简单滚动，避免无限增长
            var info = new FileInfo(LogPath);
            if (info.Exists && info.Length > 512 * 1024)
            {
                var kept = File.ReadAllLines(LogPath);
                File.WriteAllLines(LogPath, kept.Skip(kept.Length / 2));
            }
        }
        catch { }
    }
}
