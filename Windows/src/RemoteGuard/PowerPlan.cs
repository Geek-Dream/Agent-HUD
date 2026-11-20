using System.Diagnostics;

namespace RemoteGuard;

/// <summary>
/// 电源方案管理：以 powercfg 为准，读写当前电源方案的各项超时。
/// 只操作“当前活动方案”，不新建方案，避免污染用户的电源方案列表。
/// </summary>
public static class PowerPlan
{
    // 子组
    private const string SubSleep = "238c9fa8-0aad-41ed-83f4-97be242c8f20";
    private const string SubVideo = "7516b95f-f776-4464-8c53-06167f40cc99";
    private const string SubDisk = "0012ee47-9041-4b5d-9b77-535fba8b1442";

    // 设置项
    public const string SetStandbyIdle = "29f6c1db-86da-48c5-9fdb-f2b67b1f44da";
    public const string SetHibernateIdle = "9d7815a6-7ee4-497e-8888-515a05f02364";
    public const string SetUnattendSleep = "7bc4a2f9-d8fc-4469-b07b-33eb785aaca0";
    public const string SetAwayMode = "25dfa149-5dd1-4736-b5ab-e8a37b5b8187";
    public const string SetVideoIdle = "3c0bc021-c8a8-4e07-a973-6b14cbcb2b7e";
    public const string SetDiskIdle = "6738e2c4-e8a5-4a42-b16a-e040e769756e";

    /// <summary>需要备份/还原的设置项集合：[子组, 设置, 可读名称, 是否为开关型]</summary>
    public static readonly (string Sub, string Set, string Name, bool IsToggle)[] Tracked =
    {
        (SubSleep, SetStandbyIdle,     "睡眠超时",         false),
        (SubSleep, SetHibernateIdle,   "休眠超时",         false),
        (SubSleep, SetUnattendSleep,   "无人参与睡眠超时", false),
        (SubSleep, SetAwayMode,        "离开模式",         true),
        (SubVideo, SetVideoIdle,       "关闭显示器超时",   false),
        (SubDisk,  SetDiskIdle,        "关闭硬盘超时",     false),
    };

    /// <summary>开关型设置的中文描述。</summary>
    public static string DescribeValue(uint seconds, bool isToggle)
    {
        if (isToggle) return seconds != 0 ? "开启" : "关闭";
        if (seconds == 0) return "从不";
        if (seconds % 3600 == 0) return $"{seconds / 3600} 小时";
        if (seconds % 60 == 0) return $"{seconds / 60} 分钟";
        return $"{seconds} 秒";
    }

    /// <summary>单项电源设置：交流/电池两个值，单位秒。</summary>
    public sealed record SettingValue(uint Ac, uint Dc)
    {
        /// <summary>无参构造，供反序列化使用。</summary>
        public SettingValue() : this(0, 0) { }

        public override string ToString() => $"AC={Ac}s DC={Dc}s";
    }

    /// <summary>整份快照：设置项 GUID -> 值</summary>
    public sealed class Snapshot
    {
        /// <summary>
        /// 必须是可写属性才能被 System.Text.Json 反序列化填充。
        /// 之前写成只读 + 初始化器，导致读回来的 Values 永远是空字典，
        /// 还原时“没有可用快照”，电源设置被留在远程模式（已实测踩坑）。
        /// </summary>
        public Dictionary<string, SettingValue> Values { get; set; } = new();

        public string? ActiveSchemeGuid { get; set; }

        public DateTime CapturedAt { get; set; } = DateTime.Now;

        [System.Text.Json.Serialization.JsonIgnore]
        public bool IsEmpty => Values is null || Values.Count == 0;
    }

    private static string RunPowerCfg(string args)
    {
        var psi = new ProcessStartInfo("powercfg.exe", args)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = System.Text.Encoding.UTF8,
        };

        using var p = Process.Start(psi);
        if (p is null) return string.Empty;

        var output = p.StandardOutput.ReadToEnd();
        p.WaitForExit(10000);
        return output;
    }

    /// <summary>取当前活动电源方案 GUID。</summary>
    public static string? GetActiveSchemeGuid()
    {
        var output = RunPowerCfg("/getactivescheme");
        var m = System.Text.RegularExpressions.Regex.Match(
            output, @"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}");
        return m.Success ? m.Value : null;
    }

    /// <summary>
    /// 读单项设置。直接读注册表更快更稳（powercfg /q 输出解析易受本地化影响）。
    /// </summary>
    public static SettingValue? GetSetting(string schemeGuid, string subGuid, string setGuid)
    {
        var path = $@"SYSTEM\CurrentControlSet\Control\Power\User\PowerSchemes\{schemeGuid}\{subGuid}\{setGuid}";
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(path);
            if (key is null) return null;

            var ac = key.GetValue("ACSettingIndex");
            var dc = key.GetValue("DCSettingIndex");
            if (ac is null && dc is null) return null;

            return new SettingValue(
                ac is int a ? (uint)a : 0u,
                dc is int d ? (uint)d : 0u);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>采集当前活动方案里所有受跟踪设置项的完整快照。</summary>
    public static Snapshot Capture()
    {
        var snap = new Snapshot();
        var scheme = GetActiveSchemeGuid();
        snap.ActiveSchemeGuid = scheme;
        if (scheme is null) return snap;

        foreach (var (sub, set, _, _) in Tracked)
        {
            var v = GetSetting(scheme, sub, set);
            if (v is not null) snap.Values[set] = v;
        }
        return snap;
    }

    /// <summary>把快照逐项写回当前活动方案。</summary>
    public static bool Apply(Snapshot snap)
    {
        var scheme = GetActiveSchemeGuid();
        if (scheme is null || snap.IsEmpty) return false;

        var ok = true;
        foreach (var (sub, set, _, _) in Tracked)
        {
            if (!snap.Values.TryGetValue(set, out var v)) continue;
            ok &= SetValue(scheme, sub, set, v.Ac, v.Dc);
        }
        Activate(scheme);
        return ok;
    }

    /// <summary>设置单项的交流/电池值（秒）。</summary>
    public static bool SetValue(string schemeGuid, string subGuid, string setGuid, uint ac, uint dc)
    {
        var a = RunPowerCfg($"/setacvalueindex {schemeGuid} {subGuid} {setGuid} {ac}");
        var d = RunPowerCfg($"/setdcvalueindex {schemeGuid} {subGuid} {setGuid} {dc}");
        _ = a; _ = d;
        return true;
    }

    /// <summary>激活方案，让改动生效。</summary>
    public static void Activate(string schemeGuid) => RunPowerCfg($"/setactive {schemeGuid}");

    /// <summary>
    /// 应用“远程办公模式”电源参数：
    /// 永不睡眠、永不休眠、无人参与也不睡眠、允许离开模式，熄屏 5 分钟。
    /// </summary>
    public static bool ApplyRemoteMode(TimeSpan screenOffAfter)
    {
        var scheme = GetActiveSchemeGuid();
        if (scheme is null) return false;

        var offSeconds = (uint)Math.Max(0, screenOffAfter.TotalSeconds);

        // 睡眠/休眠/无人参与：0 = 从不
        SetValue(scheme, SubSleep, SetStandbyIdle, 0, 0);
        SetValue(scheme, SubSleep, SetHibernateIdle, 0, 0);
        SetValue(scheme, SubSleep, SetUnattendSleep, 0, 0);
        // 允许离开模式（远程时保持会话）
        SetValue(scheme, SubSleep, SetAwayMode, 1, 1);
        // 熄屏 5 分钟（远程画面不受影响，只关本地显示器）
        SetValue(scheme, SubVideo, SetVideoIdle, offSeconds, offSeconds);
        // 硬盘不关
        SetValue(scheme, SubDisk, SetDiskIdle, 0, 0);

        Activate(scheme);
        return true;
    }
}