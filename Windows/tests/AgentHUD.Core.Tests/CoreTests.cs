using System.Text.Json;
using AgentHUD.Core;
using Xunit;

namespace AgentHUD.Core.Tests;

public sealed class CoreTests
{
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
