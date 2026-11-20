using System.Text.Json;
using AgentHUD.Core;
using Xunit;

namespace AgentHUD.Core.Tests;

public sealed class CoreTests
{
    [Fact]
    public void SessionLimitKeepsPinnedSessionsAndNewestItems()
    {
        var now = DateTimeOffset.UtcNow;
        var sessions = Enumerable.Range(0, 12)
            .Select(index => Session($"session-{index}", AgentProvider.Codex,
                AgentStatus.Completed, now.AddMinutes(-index)))
            .ToArray();
        var pinned = new HashSet<string> { "session-11" };

        var visible = SessionDisplayPolicy.Apply(sessions, pinned, 3);

        Assert.Equal(4, visible.Count);
        Assert.Equal("session-11", visible[0].Id);
        Assert.Equal(new[] { "session-0", "session-1", "session-2" },
            visible.Skip(1).Select(session => session.Id));
        Assert.Equal(12, SessionDisplayPolicy.Apply(sessions, pinned, 0).Count);
        Assert.Equal(10, SessionDisplayPolicy.NormalizeLimit(999));
    }

    [Fact]
    public void TitlePriorityPrefersUserThenAiThenLocal()
    {
        var resolver = new SessionTitleResolver();
        var manual = new Dictionary<string, string> { ["session"] = "日志查询" };
        var ai = new Dictionary<string, string> { ["session"] = "查询日志报错" };

        var userTitle = resolver.Resolve("session", "本地标题", manual, ai);
        Assert.Equal("日志查询", userTitle.Value);
        Assert.Equal(TitleSource.User, userTitle.Source);

        manual.Clear();
        var aiTitle = resolver.Resolve("session", "本地标题", manual, ai);
        Assert.Equal("查询日志报错", aiTitle.Value);
        Assert.Equal(TitleSource.AI, aiTitle.Source);

        ai.Clear();
        var localTitle = resolver.Resolve("session", "本地标题", manual, ai);
        Assert.Equal("本地标题", localTitle.Value);
        Assert.Equal(TitleSource.Automatic, localTitle.Source);
    }

    [Fact]
    public void AutomaticTitleUsesPromptSummaryAndContinuationFallback()
    {
        Assert.Equal(
            "脚本是否可以操作oss删除",
            TextTools.AutomaticTaskTitle(
                "oss写一个sh脚本，上传成功了，是否可以删除上传的文件",
                "deploy"));
        Assert.Equal(
            "处理Agent-HUD项目任务",
            TextTools.AutomaticTaskTitle("继续", "Agent-HUD"));
    }

    [Fact]
    public void ChatCompletionsUriAppendsEndpointPath()
    {
        var configuration = new AIConfiguration
        {
            Endpoint = "https://example.com/v1/",
            Model = "test-model"
        };

        Assert.Equal(
            "https://example.com/v1/chat/completions",
            configuration.ChatCompletionsUri?.AbsoluteUri);
        Assert.False(configuration.IsUsable);

        configuration.Enabled = true;
        Assert.True(configuration.IsUsable);
    }

    [Fact]
    public void FiltersAndOrderingKeepImportantAndRunningSessionsFirst()
    {
        var now = DateTimeOffset.UtcNow;
        var working = Session("codex:working", AgentProvider.Codex, AgentStatus.Working, now);
        var waiting = Session("claude:waiting", AgentProvider.Claude, AgentStatus.WaitingUser, now.AddMinutes(-1));
        var completed = Session("pi:completed", AgentProvider.Pi, AgentStatus.Completed, now.AddMinutes(-2));
        var important = Session("claude:important", AgentProvider.Claude, AgentStatus.Completed, now.AddMinutes(-3));

        var ordered = SessionOrdering.Sort(
            new[] { waiting, completed, working, important },
            new HashSet<string> { important.Id },
            runningFirst: true);

        Assert.Equal(
            new[] { important.Id, working.Id, waiting.Id, completed.Id },
            ordered.Select(session => session.Id));
        Assert.True(StatusFilter.Working.Matches(working.Status));
        Assert.False(StatusFilter.Completed.Matches(working.Status));
        Assert.True(ProviderFilter.Claude.Matches(waiting.Provider));
        Assert.False(ProviderFilter.Codex.Matches(waiting.Provider));
        Assert.True(ProviderFilter.OpenCode.Matches(AgentProvider.OpenCode));
        Assert.False(ProviderFilter.OpenCode.Matches(AgentProvider.Codex));
    }

    [Fact]
    public void StatusRankReadsRunningWaitingCompletedFailed()
    {
        // The list must read 运行中 → 等待 → 已完成 → 错误. Starting is grouped
        // with working because the user reads both as "still running".
        Assert.Equal(AgentStatus.Working.SortRank(), AgentStatus.Starting.SortRank());
        Assert.True(AgentStatus.Working.SortRank() < AgentStatus.WaitingUser.SortRank());
        Assert.True(AgentStatus.WaitingUser.SortRank() < AgentStatus.Completed.SortRank());
        Assert.True(AgentStatus.Completed.SortRank() < AgentStatus.Failed.SortRank());
        Assert.True(AgentStatus.Failed.SortRank() < AgentStatus.Idle.SortRank());

        var now = DateTimeOffset.UtcNow;
        var ordered = SessionOrdering.Sort(
            new[]
            {
                Session("s:failed", AgentProvider.Claude, AgentStatus.Failed, now),
                Session("s:completed", AgentProvider.Claude, AgentStatus.Completed, now),
                Session("s:waiting", AgentProvider.Claude, AgentStatus.WaitingUser, now),
                Session("s:working", AgentProvider.Claude, AgentStatus.Working, now),
                Session("s:starting", AgentProvider.Claude, AgentStatus.Starting, now)
            },
            new HashSet<string>());

        Assert.Equal(
            new[] { "s:starting", "s:working", "s:waiting", "s:completed", "s:failed" },
            ordered.Select(session => session.Id));
    }

    [Fact]
    public void CompletionDetectorOnlyReturnsRunningToCompleted()
    {
        var now = DateTimeOffset.UtcNow;
        var previous = new[]
        {
            Session("session:running", AgentProvider.Codex, AgentStatus.Working, now),
            Session("session:already-done", AgentProvider.Codex, AgentStatus.Completed, now)
        };
        var current = new[]
        {
            Session("session:running", AgentProvider.Codex, AgentStatus.Completed, now),
            Session("session:already-done", AgentProvider.Codex, AgentStatus.Completed, now)
        };

        Assert.Equal(
            new[] { "session:running" },
            SessionTransitionDetector.RunningCompletionIds(previous, current));
    }

    [Theory]
    [InlineData(AgentStatus.Starting, true, true)]
    [InlineData(AgentStatus.Working, false, false)]
    [InlineData(AgentStatus.Working, true, true)]
    [InlineData(AgentStatus.WaitingUser, false, false)]
    [InlineData(AgentStatus.WaitingUser, true, true)]
    [InlineData(AgentStatus.Failed, true, true)]
    [InlineData(AgentStatus.Completed, false, false)]
    [InlineData(AgentStatus.Completed, true, true)]
    [InlineData(AgentStatus.Idle, true, false)]
    [InlineData(AgentStatus.Unknown, true, false)]
    public void OutlinePolicySeparatesStatusAndImportance(
        AgentStatus status,
        bool isImportant,
        bool expected)
    {
        Assert.Equal(expected, SessionOutlinePolicy.ShouldShow(status, isImportant));
    }

    [Fact]
    public void ExpandedPanelSizeClampsCustomDimensions()
    {
        Assert.Equal(500, ExpandedPanelSize.ClampWidth(500));
        Assert.Equal(700, ExpandedPanelSize.ClampHeight(700));
        Assert.Equal(ExpandedPanelSize.MaxWidth, ExpandedPanelSize.ClampWidth(10_000));
        Assert.Equal(ExpandedPanelSize.MaxHeight, ExpandedPanelSize.ClampHeight(10_000));
        Assert.Equal(ExpandedPanelSize.MinWidth, ExpandedPanelSize.ClampWidth(1));
        Assert.Equal(ExpandedPanelSize.DefaultHeight, ExpandedPanelSize.ClampHeight(double.NaN));
    }

    [Fact]
    public void ImageParsersExtractDisplayableAttachments()
    {
        using var codexDocument = JsonDocument.Parse(
            """
            [
              {"type":"input_image","image_url":"data:image/png;base64,iVBORw0KGgo="},
              {"type":"local_image","path":"/tmp/does-not-exist.png"}
            ]
            """);
        var codexImages = SessionAttachmentParser.CodexImages(codexDocument.RootElement);
        Assert.Single(codexImages);
        Assert.StartsWith("data:image/png;base64,", codexImages[0].DataUrl);

        using var claudeDocument = JsonDocument.Parse(
            """
            [
              {"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"/9j/4AAQSkZJRg=="}}
            ]
            """);
        var claudeImages = SessionAttachmentParser.ClaudeImages(claudeDocument.RootElement);
        Assert.Single(claudeImages);
        Assert.Equal(
            "data:image/jpeg;base64,/9j/4AAQSkZJRg==",
            claudeImages[0].DataUrl);
        Assert.Equal("[图片1]", SessionImageAttachment.DisplayLabel(0));
    }

    [Fact]
    public void JsonlReaderSkipsPartialLinesAndKeepsValidRecords()
    {
        var path = Path.Combine(
            Path.GetTempPath(),
            $"agenthud-jsonl-{Guid.NewGuid():N}.jsonl");
        File.WriteAllText(
            path,
            """
            {"type":"user","message":{"content":"第一行"}}
            {"type":"assistant"
            {"type":"assistant","message":{"content":"第二行"}}
            """);

        try
        {
            var records = JsonlReader.Read(path);
            Assert.Equal(2, records.Count);
            Assert.Equal("user", JsonTools.String(records[0], "type"));
            Assert.Equal("assistant", JsonTools.String(records[1], "type"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void IncrementalReadResumesFromTheLastCompleteLine()
    {
        // The refresh loop relies on this to avoid re-parsing multi-megabyte
        // transcripts every 1.5 s. A half-written trailing line must stay
        // unread so the next append parses it as one complete record.
        var path = Path.Combine(
            Path.GetTempPath(),
            $"agenthud-jsonl-inc-{Guid.NewGuid():N}.jsonl");
        try
        {
            File.WriteAllText(path, "{\"type\":\"user\"}\n{\"type\":\"assis");

            var first = JsonlReader.ReadFrom(path, 0, out var offset);
            Assert.Single(first);
            Assert.Equal("user", JsonTools.String(first[0], "type"));

            File.AppendAllText(path, "tant\"}\n{\"type\":\"result\"}\n");
            var second = JsonlReader.ReadFrom(path, offset, out _);

            Assert.Equal(2, second.Count);
            Assert.Equal("assistant", JsonTools.String(second[0], "type"));
            Assert.Equal("result", JsonTools.String(second[1], "type"));
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void IncrementalReadFallsBackWhenTheFileIsShorterThanTheOffset()
    {
        // Scanner only resumes from a stored offset when the file grew past it.
        // A rotated/truncated log must be re-read from the beginning, so the
        // reader has to reject an offset beyond EOF instead of seeking past it.
        var path = Path.Combine(
            Path.GetTempPath(),
            $"agenthud-jsonl-rot-{Guid.NewGuid():N}.jsonl");
        try
        {
            File.WriteAllText(path, "{\"type\":\"old\"}\n{\"type\":\"old2\"}\n");
            JsonlReader.ReadFrom(path, 0, out var offset);
            Assert.True(offset > 0);

            File.WriteAllText(path, "{\"type\":\"new\"}\n");

            var records = JsonlReader.ReadFrom(path, offset, out _);
            Assert.True(
                records.Count == 0 || JsonTools.String(records[0], "type") != "old",
                "截断后的文件不应再返回旧内容");
        }
        finally
        {
            File.Delete(path);
        }
    }

    [Fact]
    public void PromptMentioningBugsIsNotRewrittenIntoALogHunt()
    {
        // "优化当前功能，有很多bug" used to be titled "查询一下XX项目日志报错详情"
        // just because the word "bug" appeared in the prompt.
        var title = TextTools.AutomaticTaskTitle(
            "你的任务是优化当前功能，有很多bug，而且刷新比较慢",
            "Agent-HUD");
        Assert.DoesNotContain("日志报错", title);
    }

    [Fact]
    public void ExplicitLogRequestStillProducesALogTitle()
    {
        var title = TextTools.AutomaticTaskTitle("看看今天的日志报错", "Agent-HUD");
        Assert.Contains("日志报错", title);
    }

    private static AgentSession Session(
        string id,
        AgentProvider provider,
        AgentStatus status,
        DateTimeOffset lastActivityAt) =>
        new(
            id,
            provider,
            id,
            "Agent-HUD",
            "/tmp/Agent-HUD",
            "测试会话",
            status,
            StatusConfidence.High,
            "测试动作",
            Array.Empty<string>(),
            lastActivityAt.AddMinutes(-1),
            lastActivityAt,
            status == AgentStatus.Completed ? lastActivityAt : null,
            Array.Empty<TaskRun>(),
            null,
            "/tmp/Agent-HUD/session.jsonl",
            false,
            null);
}
