using System.Text.Json;
using AgentHUD.Core;
using Xunit;

namespace AgentHUD.Core.Tests;

/// <summary>
/// Regression tests for the Claude Code transcript format. Every case here was
/// observed in real <c>~/.claude/projects/**/*.jsonl</c> files on Windows.
/// </summary>
public sealed class ClaudeAdapterTests
{
    private static readonly DateTimeOffset Now =
        DateTimeOffset.Parse("2026-11-16T00:30:00Z");

    [Fact]
    public void StringContentPromptsAreKeptAndDriveTheTitle()
    {
        // Claude stores most real prompts as a bare string in message.content.
        // The parser only understood the array form, so these were dropped and
        // the session fell back to a generic "处理XX项目任务" title.
        var session = Parse(
            """
            {"type":"user","timestamp":"2026-11-16T00:20:00Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"user","content":"优化会话列表的实时刷新速度"}}
            """,
            """
            {"type":"assistant","timestamp":"2026-11-16T00:20:05Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"assistant","content":[{"type":"text","text":"好的，我先看看扫描逻辑。"}]}}
            """);

        Assert.NotNull(session);
        Assert.Equal("优化会话列表的实时刷新速度", session.LatestUserPrompt?.Text);
        Assert.NotEqual("处理proj项目任务", session.Title);
        Assert.Contains("会话", session.Title);
    }

    [Fact]
    public void TimestamplessBookkeepingRowsDoNotBecomeTheStartTime()
    {
        // `last-prompt` / `mode` / `ai-title` rows carry no timestamp. Sorting
        // puts them first, so the head's date used to be DateTimeOffset.MinValue
        // and every session reported a year-0001 start and a 700k-hour duration.
        var session = Parse(
            """
            {"type":"last-prompt","sessionId":"s1"}
            """,
            """
            {"type":"user","timestamp":"2026-11-16T00:20:00Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"user","content":"看看扫描速度"}}
            """);

        Assert.NotNull(session);
        Assert.True(session.StartedAt.Year >= 2026, $"startedAt was {session.StartedAt:O}");
        Assert.True(session.Duration < TimeSpan.FromDays(2), $"duration was {session.Duration}");
    }

    [Fact]
    public void TurnDurationMarkerMarksTheSessionCompleted()
    {
        var session = Parse(
            """
            {"type":"user","timestamp":"2026-11-16T00:20:00Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"user","content":"改一下排序"}}
            """,
            """
            {"type":"assistant","timestamp":"2026-11-16T00:20:05Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"assistant","content":[{"type":"text","text":"已完成。"}]}}
            """,
            """
            {"type":"system","subtype":"turn_duration","timestamp":"2026-11-16T00:20:06Z","sessionId":"s1","cwd":"E:\\proj"}
            """);

        Assert.NotNull(session);
        Assert.Equal(AgentStatus.Completed, session.Status);
    }

    [Fact]
    public void PromptAfterTheLastAnswerKeepsTheSessionRunning()
    {
        // A stale `turn_duration` from the previous turn must not mark a brand
        // new prompt as finished.
        var session = Parse(
            """
            {"type":"user","timestamp":"2026-11-16T00:20:00Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"user","content":"第一轮"}}
            """,
            """
            {"type":"assistant","timestamp":"2026-11-16T00:20:05Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"assistant","content":[{"type":"text","text":"第一轮完成。"}]}}
            """,
            """
            {"type":"system","subtype":"turn_duration","timestamp":"2026-11-16T00:20:06Z","sessionId":"s1","cwd":"E:\\proj"}
            """,
            """
            {"type":"user","timestamp":"2026-11-16T00:25:00Z","sessionId":"s1","cwd":"E:\\proj",
             "message":{"role":"user","content":"第二轮，继续优化"}}
            """);

        Assert.NotNull(session);
        Assert.Equal(AgentStatus.Working, session.Status);
    }

    [Fact]
    public void RunningSubagentKeepsTheParentWorking()
    {
        var subagent = new[]
        {
            Json(
                """
                {"type":"assistant","isSidechain":true,"timestamp":"2026-11-16T00:29:40Z","sessionId":"s1","cwd":"E:\\proj",
                 "message":{"role":"assistant","content":[{"type":"text","text":"子任务仍在运行"}]}}
                """)
        };

        var session = ClaudeAdapter.Parse(
            new[]
            {
                Json(
                    """
                    {"type":"user","timestamp":"2026-11-16T00:20:00Z","sessionId":"s1","cwd":"E:\\proj",
                     "message":{"role":"user","content":"并行改两个文件"}}
                    """),
                Json(
                    """
                    {"type":"assistant","timestamp":"2026-11-16T00:20:05Z","sessionId":"s1","cwd":"E:\\proj",
                     "message":{"role":"assistant","content":[{"type":"text","text":"已派发子任务。"}]}}
                    """),
                Json(
                    """
                    {"type":"system","subtype":"turn_duration","timestamp":"2026-11-16T00:20:06Z","sessionId":"s1","cwd":"E:\\proj"}
                    """)
            },
            Path.Combine(Path.GetTempPath(), "s1.jsonl"),
            Now,
            providerIsRunning: true,
            Now,
            subagent);

        Assert.NotNull(session);
        Assert.Equal(AgentStatus.Working, session.Status);
    }

    private static AgentSession? Parse(params string[] lines)
    {
        return ClaudeAdapter.Parse(
            lines.Select(Json).ToArray(),
            Path.Combine(Path.GetTempPath(), "session.jsonl"),
            Now,
            providerIsRunning: false,
            Now);
    }

    private static JsonElement Json(string line)
    {
        using var document = JsonDocument.Parse(line);
        return document.RootElement.Clone();
    }
}
