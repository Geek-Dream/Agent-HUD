using System.Text.RegularExpressions;

namespace AgentHUD.Core;

public static partial class TextTools
{
    private static readonly HashSet<string> ContinuationPrompts = new(StringComparer.OrdinalIgnoreCase)
    {
        "继续", "继续吧", "请继续", "请继续吧", "继续做", "继续做吧",
        "继续处理", "继续处理吧", "接着", "接着来", "接着做", "往下",
        "下一步", "可以继续", "好", "好的", "可以", "开始吧", "做吧",
        "干吧", "嗯", "是的", "确认", "确认一下", "已确认", "收到",
        "知道了", "明白", "了解了", "continue", "continue please",
        "please continue", "go on", "keep going", "proceed", "next",
        "ok", "okay", "yes", "do it", "go ahead"
    };

    private static readonly string[] BoilerplatePrefixes =
    {
        "<environment_context>", "<permissions", "# AGENTS.md", "## AGENTS.md",
        "You are Codex", "You are an AI assistant"
    };

    private static readonly string[] TitleLeadIns =
    {
        "这是一个空项目", "现在", "你帮我", "帮我", "请你", "请帮忙",
        "麻烦你", "麻烦", "需要你", "你", "先"
    };

    private static readonly (string Phrase, string[] Terms, int Weight)[] TitleConcepts =
    {
        ("自动标题", new[] { "自动标题", "自动命名", "标题", "命名", "备注" }, 8),
        ("后台运行方式", new[] { "后台", "前台", "焦点", "鼠标", "键盘", "操控" }, 8),
        ("拖动与固定", new[] { "拖动", "拖拽", "移动", "固定" }, 8),
        ("状态配色", new[] { "配色", "颜色", "霓虹", "半透明", "透光", "看不清", "太淡" }, 7),
        ("缩放控件", new[] { "放大", "缩小", "缩放" }, 7),
        ("折叠动画", new[] { "折叠", "收起", "丝滑" }, 7),
        ("启动器", new[] { "启动器", "启动的东西", "点击可以启动", "点击启动" }, 8),
        ("Agent筛选", new[] { "筛选项", "筛选", "过滤", "codex", "claude", "pi" }, 7),
        ("会话数量统计", new[] { "数据对不上", "数量", "统计", "显示全部", "多少个" }, 8),
        ("界面动画", new[] { "动画", "过渡" }, 5),
        ("浮窗列表", new[] { "浮窗", "列表", "面板" }, 5),
        ("任务详情", new[] { "详情", "总结", "完成说明" }, 4),
        ("页面布局", new[] { "页面", "布局", "界面" }, 4),
        ("需求文档", new[] { "需求", "文档", "requirements" }, 4),
        ("测试验证", new[] { "测试", "验证", "检查" }, 3),
        ("接口", new[] { "接口", "api" }, 3)
    };

    public static string NormalizeWhitespace(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        return WhitespaceRegex().Replace(value.Replace('\u0000', ' '), " ").Trim();
    }

    public static string? MeaningfulPrompt(string? value)
    {
        var stripped = StripInjectedPromptContent(value);
        if (string.IsNullOrWhiteSpace(stripped))
        {
            return null;
        }

        var lines = new List<string>();
        foreach (var line in stripped.Split('\n'))
        {
            var candidate = NormalizeWhitespace(line);
            if (candidate.Length == 0
                || candidate.StartsWith("```", StringComparison.Ordinal)
                || BoilerplatePrefixes.Any(candidate.StartsWith)
                || candidate.StartsWith("<", StringComparison.Ordinal)
                || (candidate.StartsWith("[", StringComparison.Ordinal) && candidate.Length <= 20))
            {
                continue;
            }
            lines.Add(candidate);
        }

        var joined = NormalizeWhitespace(string.Join(" ", lines));
        return joined.Length == 0 ? null : joined[..Math.Min(600, joined.Length)];
    }

    public static string UserPromptText(string? value, int limit = 12000)
    {
        var stripped = StripInjectedPromptContent(value);
        return stripped.Length <= limit ? stripped : stripped[..limit];
    }

    public static bool IsContinuationPrompt(string? value)
    {
        var normalized = NormalizeWhitespace(value)
            .Trim(' ', '\t', '\r', '\n', '.', ',', '，', '。', '!', '！', '?', '？', ':', '：', ';', '；')
            .ToLowerInvariant();
        return ContinuationPrompts.Contains(normalized);
    }

    public static string TitleLine(string? value, int limit = 72)
    {
        var cleaned = MeaningfulPrompt(value) ?? NormalizeWhitespace(value);
        if (cleaned.Length == 0)
        {
            return "未命名任务";
        }

        cleaned = cleaned.Replace("**", string.Empty).Replace("`", string.Empty).Trim('#', '-', '*', ' ', '>');
        return cleaned[..Math.Min(limit, cleaned.Length)];
    }

    public static string AutomaticTaskTitle(
        string? rawPrompt,
        string? projectName = null,
        string? suggestedTitle = null,
        int limit = 30)
    {
        var project = NormalizeProjectName(projectName);
        var raw = NormalizeWhitespace(rawPrompt);

        if (raw.Length > 0 && !IsContinuationPrompt(raw))
        {
            return PromptBasedTitle(raw, project, limit);
        }

        if (!string.IsNullOrWhiteSpace(suggestedTitle))
        {
            var candidate = CleanTaskText(suggestedTitle);
            if (candidate.Length is >= 2 and <= 36 && !ContainsTechnicalNoise(candidate))
            {
                return candidate[..Math.Min(limit, candidate.Length)];
            }
        }

        return project is null ? "处理项目任务" : $"处理{project}项目任务";
    }

    public static string Sentence(string? value, int limit = 360)
    {
        var cleaned = NormalizeWhitespace(value);
        if (cleaned.Length == 0)
        {
            return "没有可用的完成说明。";
        }
        return cleaned[..Math.Min(limit, cleaned.Length)];
    }

    public static IReadOnlyList<string> Unique(IEnumerable<string> values)
    {
        var seen = new HashSet<string>(StringComparer.Ordinal);
        var result = new List<string>();
        foreach (var value in values)
        {
            var clean = NormalizeWhitespace(value);
            if (clean.Length > 0 && seen.Add(clean))
            {
                result.Add(clean);
            }
        }
        return result;
    }

    public static string ReadableAction(string? value)
    {
        var action = NormalizeWhitespace(value);
        if (action.Length == 0)
        {
            return "执行工具操作";
        }
        return action.Length <= 140 ? action : action[..140];
    }

    public static string FileName(string? path)
    {
        if (string.IsNullOrWhiteSpace(path))
        {
            return string.Empty;
        }
        try
        {
            return Path.GetFileName(path.TrimEnd('\\', '/'));
        }
        catch
        {
            return path;
        }
    }

    private static string PromptBasedTitle(string raw, string? project, int limit)
    {
        var lower = raw.ToLowerInvariant();
        var projectComponent = project is null ? string.Empty : $"{project}项目";
        var lead = StripTitleLeadIns(CleanTaskText(raw));
        var mentionsOss = lower.Contains("oss") || raw.Contains("对象存储");
        var mentionsScript = lower.Contains("脚本") || lower.Contains(".sh") || lower.Contains("shell");
        var mentionsDelete = lower.Contains("删除") || lower.Contains("移除")
            || lower.Contains("delete") || lower.Contains("remove");
        if (mentionsOss && mentionsScript && mentionsDelete)
        {
            return Limit("脚本是否可以操作oss删除", limit);
        }

        var mentionsDocument = lower.Contains("requirements") || lower.Contains(".md")
            || raw.Contains("文档") || raw.Contains("需求");
        if (mentionsDocument && new[] { "读取", "阅读", "理解", "梳理" }.Any(lead.StartsWith))
        {
            return Limit($"梳理{projectComponent}需求", limit);
        }

        var logLead = lead[..Math.Min(80, lead.Length)].ToLowerInvariant();
        if (new[] { "日志", "报错", "异常", "error", "bug" }.Any(logLead.Contains))
        {
            var action = raw.Contains("修复") ? "修复" : "查询一下";
            return Limit($"{action}{projectComponent}日志报错详情", limit);
        }

        var cleaned = StripTitleLeadIns(CleanTaskText(raw));
        if (cleaned.Length == 0)
        {
            return project is null ? "处理项目任务" : $"处理{project}项目任务";
        }

        var actionName = InferAction(cleaned);
        var objectName = InferObject(cleaned);
        if (!string.IsNullOrWhiteSpace(objectName) && objectName != project)
        {
            var withProject = $"{actionName}{projectComponent}{objectName}";
            if (withProject.Length <= limit)
            {
                return withProject;
            }
            var withoutProject = $"{actionName}{objectName}";
            if (withoutProject.Length <= limit)
            {
                return withoutProject;
            }
            return Limit(withProject, limit);
        }

        if (cleaned.Length <= Math.Min(limit, 28)
            && new[] { "完善", "设计", "实现", "修复", "优化", "检查", "查询", "添加", "新增", "创建", "启动", "梳理", "验证", "调整" }
                .Any(cleaned.StartsWith))
        {
            return Limit(cleaned, limit);
        }

        return Limit($"{actionName}{projectComponent}", limit);
    }

    private static string InferAction(string value)
    {
        var lower = value.ToLowerInvariant();
        if (new[] { "修复", "解决", "不可", "无法", "对不上", "不正确", "不对", "报错", "异常", "问题", "bug", "失败" }
            .Any(lower.Contains))
        {
            return "修复";
        }
        if (new[] { "优化", "完善", "调整", "提升", "确保", "太丑", "太淡", "看不清", "不好", "修改为", "改成" }
            .Any(lower.Contains))
        {
            return "优化";
        }
        if (new[] { "搞个", "加个", "弄个", "做一个", "新增", "添加" }.Any(lower.Contains))
        {
            return "添加";
        }
        if (new[] { "实现", "开发", "搭建", "创建" }.Any(value.Contains))
        {
            return "实现";
        }
        if (new[] { "启动", "运行", "部署" }.Any(value.Contains))
        {
            return "启动";
        }
        if (new[] { "测试", "验证", "检查", "核对" }.Any(value.Contains))
        {
            return "检查";
        }
        if (new[] { "查询", "分析", "排查", "定位", "看看", "为啥", "为什么" }.Any(value.Contains))
        {
            return "查询";
        }
        if (new[] { "读取", "阅读", "理解", "梳理" }.Any(value.Contains))
        {
            return "梳理";
        }
        return "处理";
    }

    private static string? InferObject(string value)
    {
        var lower = value.ToLowerInvariant();
        var ranked = TitleConcepts
            .Select(concept =>
            {
                var matched = concept.Terms.Where(lower.Contains).ToArray();
                var firstIndex = matched
                    .Select(term => lower.IndexOf(term, StringComparison.Ordinal))
                    .Where(index => index >= 0)
                    .DefaultIfEmpty(int.MaxValue)
                    .Min();
                return (concept.Phrase, Score: matched.Length == 0
                    ? 0
                    : concept.Weight + matched.Length * 2, firstIndex);
            })
            .Where(item => item.Score > 0)
            .OrderByDescending(item => item.Score)
            .ThenBy(item => item.firstIndex)
            .ToArray();

        return ranked.Length == 0 ? null : ranked[0].Phrase;
    }

    private static string CleanTaskText(string? value)
    {
        var text = StripInjectedPromptContent(value);
        text = CodeBlockRegex().Replace(text, " ");
        text = HtmlTagRegex().Replace(text, " ");
        text = UrlRegex().Replace(text, " ");
        text = PathRegex().Replace(text, " ");
        text = WindowsPathRegex().Replace(text, " ");
        text = FileNameRegex().Replace(text, " ");
        text = text.Replace("**", string.Empty)
            .Replace("`", string.Empty)
            .Replace("#", " ")
            .Replace(">", " ");
        return NormalizeWhitespace(text);
    }

    private static string StripTitleLeadIns(string value)
    {
        var text = value;
        var changed = true;
        while (changed)
        {
            changed = false;
            text = text.Trim(' ', '\t', '\r', '\n', '.', ',', '，', '。');
            foreach (var prefix in TitleLeadIns)
            {
                if (!text.StartsWith(prefix, StringComparison.Ordinal))
                {
                    continue;
                }
                text = text[prefix.Length..];
                changed = true;
                break;
            }
        }
        return text.Trim(' ', '\t', '\r', '\n', '.', ',', '，', '。', '!', '！', '?', '？');
    }

    private static string StripInjectedPromptContent(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        var text = value.Replace("\r\n", "\n").Replace('\r', '\n');
        var normalized = NormalizeWhitespace(text);
        if (normalized.StartsWith("# AGENTS.md", StringComparison.Ordinal)
            || normalized.StartsWith("## AGENTS.md", StringComparison.Ordinal))
        {
            return string.Empty;
        }

        text = EnvironmentContextRegex().Replace(text, string.Empty);
        text = PermissionsRegex().Replace(text, string.Empty);
        text = HookPromptRegex().Replace(text, string.Empty);
        text = ImageBlockRegex().Replace(text, string.Empty);
        text = ImageTagRegex().Replace(text, string.Empty);
        return text.Trim();
    }

    private static string? NormalizeProjectName(string? value)
    {
        var name = NormalizeWhitespace(value);
        if (name.Length == 0)
        {
            return null;
        }
        name = name.TrimEnd('\\', '/');
        var separator = Math.Max(name.LastIndexOf('/'), name.LastIndexOf('\\'));
        if (separator >= 0)
        {
            name = name[(separator + 1)..];
        }
        if (name.EndsWith(".git", StringComparison.OrdinalIgnoreCase))
        {
            name = name[..^4];
        }
        return name.Length == 0 || name == "未知项目" ? null : name[..Math.Min(24, name.Length)];
    }

    private static bool ContainsTechnicalNoise(string value) =>
        value.Contains("http://", StringComparison.OrdinalIgnoreCase)
        || value.Contains("https://", StringComparison.OrdinalIgnoreCase)
        || value.Contains("<environment_context>", StringComparison.Ordinal)
        || value.Contains("```", StringComparison.Ordinal);

    private static string Limit(string value, int limit) =>
        value.Length <= limit ? value : value[..limit];

    [GeneratedRegex(@"\s+")]
    private static partial Regex WhitespaceRegex();

    [GeneratedRegex(@"(?is)```.*?```")]
    private static partial Regex CodeBlockRegex();

    [GeneratedRegex(@"(?is)<[^>]+>")]
    private static partial Regex HtmlTagRegex();

    [GeneratedRegex(@"(?i)https?://\S+")]
    private static partial Regex UrlRegex();

    [GeneratedRegex(@"(?i)/(?:Users|private|tmp|var|opt|Volumes)/\S+")]
    private static partial Regex PathRegex();

    [GeneratedRegex(@"(?i)[A-Z]:\\[^\s]+")]
    private static partial Regex WindowsPathRegex();

    [GeneratedRegex(@"(?i)\b[\w.-]+\.(?:md|swift|tsx?|jsx?|jsonl?|py|go|java|css|html|xml|yaml|yml|sh)\b")]
    private static partial Regex FileNameRegex();

    [GeneratedRegex(@"(?is)<environment_context>.*?</environment_context>")]
    private static partial Regex EnvironmentContextRegex();

    [GeneratedRegex(@"(?is)<permissions[^>]*>.*?</permissions>")]
    private static partial Regex PermissionsRegex();

    [GeneratedRegex(@"(?is)<hook_prompt[^>]*>.*?</hook_prompt>")]
    private static partial Regex HookPromptRegex();

    [GeneratedRegex(@"(?is)<image[^>]*>.*?</image>")]
    private static partial Regex ImageBlockRegex();

    [GeneratedRegex(@"(?is)</?image[^>]*>")]
    private static partial Regex ImageTagRegex();
}
